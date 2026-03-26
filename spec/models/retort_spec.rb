# frozen_string_literal: true

require "rails_helper"
require "securerandom"

describe Retort do
  def unique_value(prefix)
    "#{prefix.to_s[0, 8]}#{SecureRandom.hex(3)}"
  end

  def create_user(prefix)
    token = unique_value(prefix)
    Fabricate(:user, username: token, email: "#{token}@example.com")
  end

  def create_topic(owner:)
    Fabricate(:topic, user: owner, category: Fabricate(:category, user: owner), title: "Retort topic #{unique_value("title")}")
  end

  before(:example) {}

  let(:user) { create_user("user") }
  let(:topic_owner) { create_user("owner") }
  let(:topic) { create_topic(owner: topic_owner) }
  let(:post) { Fabricate(:post, topic: topic, user: topic_owner, raw: "retort post #{unique_value("post")}") }
  let(:another_post) do
    Fabricate(:post, topic: topic, user: topic_owner, raw: "retort post #{unique_value("post")}")
  end
  let(:another_topic_post) do
    another_owner = create_user("owner")
    another_topic = create_topic(owner: another_owner)
    Fabricate(:post, topic: another_topic, user: another_owner, raw: "retort post #{unique_value("post")}")
  end
  let(:emoji) { "kickbutt" }
  let(:altermoji) { "puntrear" }

  describe "initialize" do
    let(:retort) { Retort.create(post_id: post.id, user_id: user.id, emoji: emoji) }

    it "stores the record" do
      expect(retort.post).to eq post
      expect(retort.user).to eq user
      expect(retort.emoji).to eq emoji
    end
    it "has timestamps" do
      expect(retort.created_at).not_to be_nil
      expect(retort.updated_at).not_to be_nil
      expect(retort.updated_at).to eq_time retort.created_at
    end
    it "not deleted" do
      expect(retort.deleted_at).to be_nil
      expect(retort.deleted_by).to be_nil
    end
  end

  describe "checks ActiveRecord valid" do
    it "is invalid emoji" do
      expect { Retort.create(post_id: post.id, user_id: user.id, emoji: nil).save! }.to raise_error(
        ActiveRecord::RecordInvalid,
      )
    end
    it "is invalid post" do
      invalid_post_id = post.id + 100_000
      expect {
        Retort.create(post_id: invalid_post_id, user_id: user.id, emoji: emoji)
      }.to raise_error ActiveRecord::InvalidForeignKey
    end
    it "is valid" do
      expect { Retort.create(post_id: post.id, user_id: user.id, emoji: emoji) }.not_to raise_error
    end
  end

  describe "when create, withdraw, toggle" do
    let(:retort) { Retort.create(post_id: post.id, user_id: user.id, emoji: emoji) }

    it "can not create twice" do
      expect(retort).not_to be_nil
      expect {
        Retort.create(post_id: post.id, user_id: user.id, emoji: emoji).save!
      }.to raise_error ActiveRecord::RecordNotUnique
    end

    it "can withdraw" do
      expect { retort.trash!(user) }.to change { retort.deleted_at }.from(nil).to(
        be_present,
      ).and change { retort.deleted_by }.from(nil).to(user)
    end

    it "can recover" do
      original_created_at = retort.created_at
      retort.trash!(user)
      expect { retort.recover! }.to change { retort.deleted_at }.from(be_present).to(
        nil,
      ).and change { retort.deleted_by }.from(user).to(nil)
      expect(retort.created_at).to eq_time original_created_at
      expect(retort.updated_at).not_to eq_time original_created_at
    end
  end
end
