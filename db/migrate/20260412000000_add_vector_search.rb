class AddVectorSearch < ActiveRecord::Migration[8.1]
  def change
    enable_extension "vector" unless extension_enabled?("vector")

    create_table :record_embeddings, id: :uuid do |t|
      t.references :knowledge_record, type: :uuid, null: false, foreign_key: true, index: true
      t.column :embedding, :vector, limit: 768
      t.integer :chunk_index, null: false, default: 0
      t.text :chunk_text, null: false
      t.string :model_id, null: false

      t.timestamps
    end

    add_index :record_embeddings, :embedding, using: :hnsw, opclass: :vector_cosine_ops
    add_index :record_embeddings, :model_id
  end
end
