class CreateKnowledgeRecords < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")

    create_table :knowledge_records, id: :uuid do |t|
      t.string :shortlink, null: false
      t.string :title, null: false
      t.text :summary
      t.text :content, null: false
      t.string :knowledge_type, null: false
      t.string :project, null: false
      t.string :tags, array: true, default: []
      t.string :created_by

      t.timestamps
    end

    add_index :knowledge_records, :shortlink, unique: true
    add_index :knowledge_records, :project
    add_index :knowledge_records, :knowledge_type
    add_index :knowledge_records, :tags, using: :gin
  end
end
