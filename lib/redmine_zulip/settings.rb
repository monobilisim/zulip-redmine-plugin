module RedmineZulip
  class Settings
    # Accepts anything that owns a project (Issue, WikiContent, News, Message,
    # Document, Comment, Attachment) or a Project itself.
    def initialize(projectable)
      @project = projectable.respond_to?(:project) ? projectable.project : projectable
      @issue = projectable if projectable.is_a?(Issue)
    end

    # A destroyed record whose project is already gone resolves to no project,
    # and every accessor below needs one.
    def enabled?
      @project.present? &&
        zulip_url.present? && zulip_email.present? && zulip_api_key.present?
    end

    def zulip_url
      @project.zulip_url.present? ?
        @project.zulip_url : Setting.plugin_redmine_zulip["zulip_url"]
    end

    def zulip_email
      @project.zulip_email.present? ?
        @project.zulip_email : Setting.plugin_redmine_zulip["zulip_email"]
    end

    def zulip_api_key
      @project.zulip_api_key.present? ?
        @project.zulip_api_key :
        Setting.plugin_redmine_zulip["zulip_api_key"]
    end

    def stream
      evaluate_expression(
        @project.zulip_stream_expression.present? ?
          @project.zulip_stream_expression :
          Setting.plugin_redmine_zulip["zulip_stream_expression"]
      )
    end

    def issue_updates_subject
      evaluate_expression(
        @project.zulip_issue_updates_subject_expression.present? ?
          @project.zulip_issue_updates_subject_expression :
          Setting.plugin_redmine_zulip["zulip_issue_updates_subject_expression"]
      )
    end

    def version_updates_subject
      evaluate_expression(
        @project.zulip_version_updates_subject_expression.present? ?
          @project.zulip_version_updates_subject_expression :
          Setting.plugin_redmine_zulip["zulip_version_updates_subject_expression"]
      )
    end

    private

    # ${issue_*} variables only resolve for issue notifications; they are empty
    # for every other activity event.
    def evaluate_expression(expression)
      return nil if expression.nil?
      expression.gsub("${issue_id}", @issue ? @issue.id.to_s : "")
                .gsub("${issue_subject}", @issue ? @issue.subject_without_punctuation : "")
                .gsub("${project_name}", @project.name)
                .gsub("${project_identifier}", @project.identifier)
                .gsub("${version_name}", @issue&.fixed_version&.name.to_s)
    end
  end
end
