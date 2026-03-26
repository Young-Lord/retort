# frozen_string_literal: true

require "rails_helper"
require "securerandom"

RSpec.describe "Retort user lifecycle integration" do
  def unique_value(prefix)
    "#{prefix}#{SecureRandom.hex(4)}"
  end

  def create_user(prefix)
    token = unique_value(prefix)
    Fabricate(:user, username: token, email: "#{token}@example.com")
  end

  def create_post(owner:)
    token = unique_value("retort")
    category =
      Fabricate(:category, user: owner, name: "category-#{token}", slug: "category-#{token}")
    topic =
      Fabricate(:topic, user: owner, category: category, title: "Retort lifecycle title #{token}")
    Fabricate(
      :post,
      topic: topic,
      user: owner,
      raw: "This is a verification post body for retort lifecycle #{token}.",
    )
  end

  def merge_users!(source_user, target_user)
    UserMerger.new(source_user, target_user).merge!
  end

  def destroy_user!(user)
    UserDestroyer.new(Discourse.system_user).destroy(user, quiet: true)
  end

  describe "during user merge" do
    it "reassigns active retorts to the target user and refreshes serializer output" do
      source_user = create_user("source")
      target_user = create_user("target")
      post = create_post(owner: target_user)
      Retort.create!(post: post, user: source_user, emoji: "heart")

      serializer = PostSerializer.new(post.reload, scope: Guardian.new(target_user), root: false)
      expect(serializer.retorts).to eq(
        [{ post_id: post.id, usernames: [source_user.username], emoji: "heart" }],
      )
      expect(serializer.my_retorts).to eq([])

      merge_users!(source_user, target_user)

      expect(User.exists?(source_user.id)).to eq(false)
      expect(Retort.where(user_id: target_user.id).pluck(:emoji)).to eq(["heart"])

      post_serializer =
        PostSerializer.new(post.reload, scope: Guardian.new(target_user), root: false)
      expect(post_serializer.retorts).to eq(
        [{ post_id: post.id, usernames: [target_user.username], emoji: "heart" }],
      )
      expect(post_serializer.my_retorts.pluck(:emoji)).to eq(["heart"])
    end

    it "reassigns soft-deleted retorts without failing the merge" do
      source_user = create_user("source")
      target_user = create_user("target")
      post = create_post(owner: target_user)
      retort = Retort.create!(post: post, user: source_user, emoji: "heart")
      retort.trash!(source_user)

      expect { merge_users!(source_user, target_user) }.not_to raise_error

      expect(User.exists?(source_user.id)).to eq(false)
      moved_retort =
        Retort.with_deleted.find_by(post_id: post.id, user_id: target_user.id, emoji: "heart")
      expect(moved_retort).to be_present
      expect(moved_retort.deleted_by_id).to eq(target_user.id)
    end

    it "keeps the source retort when it is active and the target duplicate is deleted" do
      source_user = create_user("source")
      target_user = create_user("target")
      post = create_post(owner: target_user)

      source_retort = Retort.create!(post: post, user: source_user, emoji: "heart")
      target_retort = Retort.create!(post: post, user: target_user, emoji: "heart")
      target_retort.trash!(target_user)

      merge_users!(source_user, target_user)

      retained_retort =
        Retort.with_deleted.find_by(post_id: post.id, user_id: target_user.id, emoji: "heart")
      expect(retained_retort.id).to eq(source_retort.id)
      expect(retained_retort).not_to be_trashed
    end

    it "keeps the target retort when the source duplicate is deleted" do
      source_user = create_user("source")
      target_user = create_user("target")
      post = create_post(owner: target_user)

      source_retort = Retort.create!(post: post, user: source_user, emoji: "heart")
      source_retort.trash!(source_user)
      target_retort = Retort.create!(post: post, user: target_user, emoji: "heart")

      merge_users!(source_user, target_user)

      retained_retort =
        Retort.with_deleted.find_by(post_id: post.id, user_id: target_user.id, emoji: "heart")
      expect(retained_retort.id).to eq(target_retort.id)
      expect(retained_retort).not_to be_trashed
    end

    it "keeps the target retort when both duplicates are active" do
      source_user = create_user("source")
      target_user = create_user("target")
      post = create_post(owner: target_user)

      Retort.create!(post: post, user: source_user, emoji: "heart")
      target_retort = Retort.create!(post: post, user: target_user, emoji: "heart")

      merge_users!(source_user, target_user)

      retained_retort =
        Retort.with_deleted.find_by(post_id: post.id, user_id: target_user.id, emoji: "heart")
      expect(retained_retort.id).to eq(target_retort.id)
      expect(
        Retort.with_deleted.where(post_id: post.id, user_id: target_user.id, emoji: "heart").count,
      ).to eq(1)
    end

    it "keeps the target retort when both duplicates are deleted" do
      source_user = create_user("source")
      target_user = create_user("target")
      post = create_post(owner: target_user)

      source_retort = Retort.create!(post: post, user: source_user, emoji: "heart")
      source_retort.trash!(source_user)
      target_retort = Retort.create!(post: post, user: target_user, emoji: "heart")
      target_retort.trash!(target_user)

      merge_users!(source_user, target_user)

      retained_retort =
        Retort.with_deleted.find_by(post_id: post.id, user_id: target_user.id, emoji: "heart")
      expect(retained_retort.id).to eq(target_retort.id)
      expect(retained_retort).to be_trashed
    end

    it "reassigns deleted_by_id references from the source user to the target user" do
      source_user = create_user("source")
      target_user = create_user("target")
      other_user = create_user("other")
      post = create_post(owner: target_user)
      other_retort = Retort.create!(post: post, user: other_user, emoji: "heart")
      other_retort.trash!(source_user)

      merge_users!(source_user, target_user)

      expect(other_retort.reload.deleted_by_id).to eq(target_user.id)
    end
  end

  describe "during user deletion" do
    it "deletes active retorts owned by the deleted user" do
      user = create_user("delete")
      post_owner = create_user("owner")
      post = create_post(owner: post_owner)
      Retort.create!(post: post, user: user, emoji: "heart")

      expect { destroy_user!(user) }.to change { User.exists?(user.id) }.from(true).to(false)
      expect(Retort.with_deleted.where(post_id: post.id, user_id: user.id)).to be_empty
    end

    it "deletes soft-deleted retorts before removing the user row" do
      user = create_user("delete")
      post_owner = create_user("owner")
      post = create_post(owner: post_owner)
      retort = Retort.create!(post: post, user: user, emoji: "heart")
      retort.trash!(user)

      expect { destroy_user!(user) }.to change { User.exists?(user.id) }.from(true).to(false)
      expect(Retort.with_deleted.where(post_id: post.id, user_id: user.id)).to be_empty
    end

    it "deletes active and soft-deleted owned retorts in one destroy operation" do
      user = create_user("delete")
      post_owner = create_user("owner")
      first_post = create_post(owner: post_owner)
      second_post = create_post(owner: post_owner)

      Retort.create!(post: first_post, user: user, emoji: "heart")
      deleted_retort = Retort.create!(post: second_post, user: user, emoji: "+1")
      deleted_retort.trash!(user)

      expect { destroy_user!(user) }.to change { User.exists?(user.id) }.from(true).to(false)
      expect(Retort.with_deleted.where(user_id: user.id)).to be_empty
    end

    it "reassigns deleted_by_id on other users' retorts to system" do
      user = create_user("delete")
      other_user = create_user("other")
      post = create_post(owner: other_user)
      other_retort = Retort.create!(post: post, user: other_user, emoji: "heart")
      other_retort.trash!(user)

      expect { destroy_user!(user) }.to change { User.exists?(user.id) }.from(true).to(false)
      expect(other_retort.reload.deleted_by_id).to eq(Discourse.system_user.id)
    end
  end
end
