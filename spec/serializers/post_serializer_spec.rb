# frozen_string_literal: true

require "rails_helper"
require "securerandom"

RSpec.describe PostSerializer do
  def unique_value(prefix)
    "#{prefix}#{SecureRandom.hex(4)}"
  end

  def create_user(prefix)
    token = unique_value(prefix)
    Fabricate(:user, username: token, email: "#{token}@example.com")
  end

  let(:post_owner) { create_user("owner") }
  let(:post) do
    token = unique_value("serializer")
    category =
      Fabricate(:category, user: post_owner, name: "category-#{token}", slug: "category-#{token}")
    topic =
      Fabricate(:topic, user: post_owner, category: category, title: "Serializer topic #{token}")
    Fabricate(:post, topic: topic, user: post_owner, raw: "Serializer body #{token}")
  end
  let(:user1) { create_user("user1") }
  let(:user2) { create_user("user2") }

  before(:example) do
    Retort.create(post_id: post.id, user_id: user1.id, emoji: "heart")
    Retort.create(post_id: post.id, user_id: user2.id, emoji: "heart")
    Retort.create(post_id: post.id, user_id: user1.id, emoji: "+1")
  end

  describe "#retorts" do
    it "serializes retorts grouped by emoji" do
      post_serializer = PostSerializer.new(post, scope: Guardian.new).as_json[:post]
      expect(post_serializer[:retorts].length).to eq(2)
      expect(post_serializer[:retorts][0][:emoji]).to eq("heart")
      expect(post_serializer[:retorts][0][:usernames]).to eq([user1.username, user2.username])
      expect(post_serializer[:retorts][1][:emoji]).to eq("+1")
      expect(post_serializer[:retorts][1][:usernames]).to eq([user1.username])
    end

    it "reuses the cached retort payload" do
      PostSerializer.new(post, scope: Guardian.new).as_json
      Retort.expects(:where).never
      PostSerializer.new(post, scope: Guardian.new).as_json
    end
  end

  describe "#my_retorts" do
    it "serializes the current user's retorts" do
      post_serializer = PostSerializer.new(post, scope: Guardian.new(user1)).as_json[:post]
      expect(post_serializer[:my_retorts].length).to eq(2)
      expect(post_serializer[:my_retorts].pluck(:emoji)).to match_array(%w[heart +1])
      expect(post_serializer[:my_retorts].pluck(:updated_at).compact.length).to eq(2)
    end

    it "returns an empty list for anonymous users" do
      post_serializer = PostSerializer.new(post, scope: Guardian.new).as_json[:post]
      expect(post_serializer[:my_retorts]).to eq([])
    end
  end

  describe "#can_retort" do
    it "returns true for a signed-in user" do
      expect(
        PostSerializer.new(post, scope: Guardian.new(user1)).as_json[:post][:can_retort],
      ).to eq(true)
    end

    it "returns false for anonymous users" do
      expect(PostSerializer.new(post, scope: Guardian.new).as_json[:post][:can_retort]).to eq(false)
    end
  end

  describe "#can_remove_retort" do
    it "returns false for non-staff users" do
      expect(
        PostSerializer.new(post, scope: Guardian.new(user1)).as_json[:post][:can_remove_retort],
      ).to eq(false)
    end

    it "returns true for staff users" do
      staff =
        Fabricate(
          :admin,
          username: unique_value("admin"),
          email: "#{unique_value("admin")}@example.com",
        )
      expect(
        PostSerializer.new(post, scope: Guardian.new(staff)).as_json[:post][:can_remove_retort],
      ).to eq(true)
    end
  end
end
