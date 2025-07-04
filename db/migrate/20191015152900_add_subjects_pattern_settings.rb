class AddSubjectsPatternSettings < ActiveRecord::Migration[5.2]
  def change
    rename_column :projects, :zulip_stream, :zulip_stream_expression
    add_column :projects, :zulip_issue_updates_subject_expression,   :string
    add_column :projects, :zulip_version_updates_subject_expression, :string
    #execute "UPDATE projects SET zulip_issue_updates_subject_expression = '${project_identifier}'"
    #execute "UPDATE projects SET zulip_version_updates_subject_expression = ""
  end
end
