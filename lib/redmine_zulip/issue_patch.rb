module RedmineZulip
  module IssuePatch
    extend ActiveSupport::Concern

    TWEET_SIZE = 140

    # Issue columns rendered in update notifications, in display order.
    # column => [human_attribute_name key, resolver(value)]
    CHANGE_FIELDS = {
      "assigned_to_id"   => [:assigned_to,     ->(id) { User.find_by(id: id)&.name }],
      "status_id"        => [:status,          ->(id) { IssueStatus.find_by(id: id)&.name }],
      "priority_id"      => [:priority,        ->(id) { IssuePriority.find_by(id: id)&.name }],
      "tracker_id"       => [:tracker,         ->(id) { Tracker.find_by(id: id)&.name }],
      "category_id"      => [:category,        ->(id) { IssueCategory.find_by(id: id)&.name }],
      "fixed_version_id" => [:fixed_version,   ->(id) { Version.find_by(id: id)&.name }],
      "parent_id"        => [:parent_issue,    ->(id) { Issue.find_by(id: id)&.subject }],
      "start_date"       => [:start_date,      ->(date) { zulip_format_date(date) }],
      "due_date"         => [:due_date,        ->(date) { zulip_format_date(date) }],
      "estimated_hours"  => [:estimated_hours, ->(hours) { hours.to_s }],
      "done_ratio"       => [:done_ratio,      ->(ratio) { "#{ratio}%" }]
    }.freeze

    def self.zulip_format_date(date)
      return nil if date.blank?
      I18n.l(date.to_date, format: Setting.date_format.presence)
    end

    included do
      after_commit :notify_assignment, if: proc { |issue|
        issue.zulip_settings.enabled? &&
          issue.assigned_to_id.present? &&
          issue.assigned_to_id != User.current.id &&
          issue.previous_changes.keys.include?("assigned_to_id")
      }

      after_commit :notify_unassignment, if: proc { |issue|
        issue.zulip_settings.enabled? &&
          issue.previous_changes.keys.include?("assigned_to_id") &&
          issue.previous_changes["assigned_to_id"].first.present? &&
          issue.previous_changes["assigned_to_id"].first != User.current.id
      }

      after_commit :notify_assigned_to_issue_updated, if: proc { |issue|
        issue.zulip_settings.enabled? &&
          !issue.destroyed? &&
          !issue.previous_changes.include?("id") &&
          !issue.previous_changes.include?("assigned_to_id") &&
          issue.assigned_to_id.present? &&
          issue.assigned_to_id != User.current.id
      }

      after_commit :notify_assigned_to_issue_destroyed, if: proc { |issue|
        issue.zulip_settings.enabled? &&
          issue.destroyed? &&
          issue.assigned_to_id.present? &&
          issue.assigned_to_id != User.current.id
      }

      after_commit :init_issue_subject, if: proc { |issue|
        issue.zulip_settings.enabled? &&
          issue.zulip_settings.stream.present? &&
          issue.zulip_settings.issue_updates_subject.present? &&
          issue.previous_changes.include?("id")
      }

      after_commit :update_issue_subject, if: proc { |issue|
        issue.zulip_settings.enabled? &&
          !issue.destroyed? &&
          issue.zulip_settings.stream.present? &&
          issue.zulip_settings.issue_updates_subject.present? &&
          !issue.previous_changes.include?("id")
      }

      after_commit :update_issue_subject_destroyed, if: proc { |issue|
        issue.zulip_settings.enabled? &&
          issue.destroyed? &&
          issue.zulip_settings.stream.present? &&
          issue.zulip_settings.issue_updates_subject.present?
      }

      after_commit :update_version_subject_added, if: proc { |issue|
        issue.zulip_settings.enabled? &&
          issue.zulip_settings.stream.present? &&
          issue.zulip_settings.version_updates_subject.present? &&
          issue.previous_changes.include?("fixed_version_id") &&
          issue.previous_changes["fixed_version_id"].last.present?
      }

      after_commit :update_version_subject_removed, if: proc { |issue|
        issue.zulip_settings.enabled? &&
          issue.zulip_settings.stream.present? &&
          issue.zulip_settings.version_updates_subject.present? &&
          issue.previous_changes.include?("fixed_version_id") &&
          issue.previous_changes["fixed_version_id"].first.present?
      }

      after_commit :update_version_subject_status, if: proc { |issue|
        issue.zulip_settings.enabled? &&
          issue.zulip_settings.stream.present? &&
          issue.zulip_settings.version_updates_subject.present? &&
          issue.previous_changes.include?("status_id") &&
          issue.fixed_version_id.present? &&
          !issue.previous_changes.include?("fixed_version_id")
      }

      after_commit :update_version_subject_destroyed, if: proc { |issue|
        issue.zulip_settings.enabled? &&
          issue.zulip_settings.stream.present? &&
          issue.zulip_settings.version_updates_subject.present? &&
          issue.destroyed? &&
          issue.fixed_version_id.present?
      }
    end

    def subject_without_punctuation
      subject.to_s.chomp(".")
    end

    def zulip_settings
      @_zulip_settings ||= RedmineZulip::Settings.new(self)
    end

    private

    def zulip_api
      @_zulip_api ||= RedmineZulip::Api.new(
        url: zulip_settings.zulip_url,
        email: zulip_settings.zulip_email,
        key: zulip_settings.zulip_api_key
      )
    end

    # Renders every field that changed in this save, as Zulip markdown bullets.
    def zulip_change_details(locale)
      message = ""

      if previous_changes.include?("subject")
        message += "\n* **#{Issue.human_attribute_name(:subject, locale: locale)}**: "
        message += "*~~#{previous_changes['subject'].first}~~* "
        message += subject_without_punctuation
      end

      if previous_changes.include?("description")
        message += "~~~ quote\n"
        message += description_truncated
        message += "\n~~~\n"
      end

      if notes.present?
        message += "\n* **#{Issue.human_attribute_name(:notes, locale: locale)}**\n"
        message += "~~~ quote\n"
        message += notes
        message += "\n~~~\n"
      end

      CHANGE_FIELDS.each do |column, (label, resolver)|
        next unless previous_changes.include?(column)
        previous_value, value = previous_changes[column]
        message += "\n* **#{Issue.human_attribute_name(label, locale: locale)}**: "
        message += "*~~#{resolver.call(previous_value)}~~* " if previous_value.present?
        message += resolver.call(value).to_s if value.present?
      end

      message
    end

    def notify_assignment
      locale = assigned_to.language.present? ?
                 assigned_to.language : Setting.default_language
      message = I18n.t("zulip_notify_assignment", **{
        locale: locale,
        user: User.current.name,
        id: id,
        url: url,
        status: status.name,
        project: project.name,
        subject: subject_without_punctuation,
        description: description_truncated,
        status_label: Issue.human_attribute_name(:status, locale: locale)
      })
      if fixed_version.present?
        version_label = Issue.human_attribute_name(:fixed_version, locale: locale)
        message += "* **#{version_label}**: #{fixed_version.name}\n"
      end
      if estimated_hours.present?
        estimated_hours_label = Issue.human_attribute_name(:estimated_hours, locale: locale)
        message += "* **#{estimated_hours_label}**: #{estimated_hours}\n"
      end
      zulip_api.messages.send(
        type: "private",
        content: message,
        to: assigned_to.mail
      )
    end

    def notify_unassignment
      previous_assigned_to = User.find(
        previous_changes["assigned_to_id"].first
      )
      locale = previous_assigned_to.language.present? ?
                 previous_assigned_to.language : Setting.default_language
      message = I18n.t("zulip_notify_unassignment", **{
        user: User.current.name,
        id: id,
        url: url,
        project: project.name,
        subject: subject_without_punctuation,
        locale: locale
      })
      zulip_api.messages.send(
        type: "private",
        content: message,
        to: previous_assigned_to.mail
      )
    end

    def notify_assigned_to_issue_updated
      locale = assigned_to.language.present? ?
                 assigned_to.language : Setting.default_language
      message = I18n.t("zulip_notify_updated", **{
        user: User.current.name,
        id: id,
        url: url,
        project: project.name,
        subject: subject_without_punctuation,
        locale: locale
      })
      message += zulip_change_details(locale)
      zulip_api.messages.send(
        type: "private",
        content: message,
        to: assigned_to.mail
      )
    end

    def notify_assigned_to_issue_destroyed
      locale = assigned_to.language.present? ?
                 assigned_to.language : Setting.default_language
      message = I18n.t("zulip_notify_destroyed", **{
        user: User.current.name,
        id: id,
        project: project.name,
        subject: subject_without_punctuation,
        locale: locale
      })
      zulip_api.messages.send(
        type: "private",
        content: message,
        to: assigned_to.mail
      )
    end

    def init_issue_subject
      locale = Setting.default_language
      message = I18n.t("zulip_init_issue_subject", **{
        locale: locale,
        user: User.current.name,
        id: id,
        url: url,
        project: project.name,
        subject: subject_without_punctuation,
        description: description_truncated,
        assigned_to_label: Issue.human_attribute_name(:assigned_to, locale: locale),
        assigned_to: assigned_to || "-",
        status_label: Issue.human_attribute_name(:status, locale: locale),
        status: status.nil? ? nil : status.name
      })
      if priority.present?
        priority_label = Issue.human_attribute_name(:priority, locale: locale)
        message += "* **#{priority_label}**: #{priority.name}\n"
      end
      if fixed_version.present?
        version_label = Issue.human_attribute_name(:fixed_version, locale: locale)
        message += "* **#{version_label}**: #{fixed_version.name}\n"
      end
      if estimated_hours.present?
        estimated_hours_label = Issue.human_attribute_name(:estimated_hours, locale: locale)
        message += "* **#{estimated_hours_label}**: #{estimated_hours}\n"
      end
      zulip_api.messages.send(
        type: "stream",
        content: message,
        to: zulip_settings.stream,
        subject: zulip_settings.issue_updates_subject
      )
    end

    def update_issue_subject
      locale = Setting.default_language
      message = I18n.t("zulip_notify_updated", **{
        locale: locale,
        user: User.current.name,
        id: id,
        url: url,
        project: project.name,
        subject: subject_without_punctuation,
      })
      message += zulip_change_details(locale)
      zulip_api.messages.send(
        type: "stream",
        content: message,
        to: zulip_settings.stream,
        subject: zulip_settings.issue_updates_subject
      )
    end

    def update_issue_subject_destroyed
      message = I18n.t("zulip_notify_destroyed", **{
        locale: Setting.default_language,
        user: User.current.name,
        id: id,
        project: project.name,
        subject: subject_without_punctuation
      })
      zulip_api.messages.send(
        type: "stream",
        content: message,
        to: zulip_settings.stream,
        subject: zulip_settings.issue_updates_subject
      )
    end

    def update_version_subject_added
      message = I18n.t("zulip_update_version_subject_added", **{
        locale: Setting.default_language,
        user: User.current.name,
        id: id,
        url: url,
        project: project.name,
        subject: subject_without_punctuation,
        fixed_version: fixed_version
      })
      zulip_api.messages.send(
        type: "stream",
        content: message,
        to: zulip_settings.stream,
        subject: zulip_settings.version_updates_subject
      )
    end

    def update_version_subject_removed
      previous_fixed_version = Version.find_by(
        id: previous_changes["fixed_version_id"].first
      )
      message = I18n.t("zulip_update_version_subject_removed", **{
        locale: Setting.default_language,
        user: User.current.name,
        id: id,
        url: url,
        project: project.name,
        subject: subject_without_punctuation,
        fixed_version: previous_fixed_version
      })
      zulip_api.messages.send(
        type: "stream",
        content: message,
        to: zulip_settings.stream,
        subject: zulip_settings.version_updates_subject
      )
    end

    def update_version_subject_status
      previous_status_id = previous_changes["status_id"].first
      message = I18n.t("zulip_update_version_subject_status", **{
        locale: Setting.default_language,
        user: User.current.name,
        id: id,
        url: url,
        project: project.name,
        subject: subject_without_punctuation,
        previous_status: IssueStatus.find_by(id: previous_status_id),
        current_status: status
      })
      zulip_api.messages.send(
        type: "stream",
        content: message,
        to: zulip_settings.stream,
        subject: zulip_settings.version_updates_subject
      )
    end

    def update_version_subject_destroyed
      message = I18n.t("zulip_notify_destroyed", **{
        locale: Setting.default_language,
        user: User.current.name,
        id: id,
        project: project.name,
        subject: subject_without_punctuation
      })
      zulip_api.messages.send(
        type: "stream",
        content: message,
        to: zulip_settings.stream,
        subject: zulip_settings.version_updates_subject
      )
    end

    def url
      "#{Setting[:protocol]}://#{Setting[:host_name]}/issues/#{id}"
    end

    def description_truncated
      truncated = description.to_s
      if truncated.include?("\n")
        truncated = "#{truncated.split("\n")[0]}..."
      end
      if truncated.size > TWEET_SIZE
        truncated = "#{truncated[0..(TWEET_SIZE - 1)]}..."
      end
      truncated
    end
  end
end
