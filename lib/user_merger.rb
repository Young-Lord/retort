# frozen_string_literal: true

module DiscourseRetort
  class UserMerger
    def self.merge(source_user, target_user)
      new(source_user, target_user).merge
    end

    def initialize(source_user, target_user)
      @source_user = source_user
      @target_user = target_user
      @affected_post_ids = []
    end

    def merge
      Retort.transaction do
        resolve_duplicate_retorts
        migrate_remaining_retorts
        migrate_deleted_by_ids
      end

      @affected_post_ids.uniq.each { |post_id| Retort.clear_cache(post_id) }
    end

    private

    attr_reader :source_user, :target_user, :affected_post_ids

    def resolve_duplicate_retorts
      source_retorts.find_each do |source_retort|
        target_retort = target_retorts[key_for(source_retort)]
        next if target_retort.blank?

        affected_post_ids << source_retort.post_id

        if keep_source_retort?(source_retort, target_retort)
          Retort.with_deleted.where(id: target_retort.id).delete_all
          target_retorts.delete(key_for(source_retort))
        else
          Retort.with_deleted.where(id: source_retort.id).delete_all
        end
      end
    end

    def migrate_remaining_retorts
      remaining_source_retorts = source_retorts
      affected_post_ids.concat(remaining_source_retorts.distinct.pluck(:post_id))
      remaining_source_retorts.update_all(user_id: target_user.id)
    end

    def migrate_deleted_by_ids
      retorts_with_deleted_by_source = Retort.with_deleted.where(deleted_by_id: source_user.id)
      affected_post_ids.concat(retorts_with_deleted_by_source.distinct.pluck(:post_id))
      retorts_with_deleted_by_source.update_all(deleted_by_id: target_user.id)
    end

    def source_retorts
      Retort.with_deleted.where(user_id: source_user.id)
    end

    def target_retorts
      @target_retorts ||= Retort.with_deleted.where(user_id: target_user.id).index_by { |retort| key_for(retort) }
    end

    def key_for(retort)
      [retort.post_id, retort.emoji]
    end

    def keep_source_retort?(source_retort, target_retort)
      !source_retort.trashed? && target_retort.trashed?
    end
  end
end
