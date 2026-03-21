class AddMulchCompatibleFields < ActiveRecord::Migration[8.1]
  def change
    add_column :knowledge_records, :classification, :string, null: false, default: "tactical"
    add_column :knowledge_records, :evidence, :jsonb, default: {}
    add_column :knowledge_records, :relates_to, :string, array: true, default: []
    add_column :knowledge_records, :supersedes, :string, array: true, default: []
    add_column :knowledge_records, :outcomes, :jsonb, array: true, default: []
    add_column :knowledge_records, :metadata, :jsonb, default: {}

    add_index :knowledge_records, :classification
  end
end
