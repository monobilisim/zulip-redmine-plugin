class SetDefaultPatterns < ActiveRecord::Migration[5.2]
  def change
    Setting.plugin_redmine_zulip[:zulip_stream_expression] = "${project_name}"
    Setting.plugin_redmine_zulip[:zulip_issue_updates_subject_expression] = "${project_identifier}"
  end
end
