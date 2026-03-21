class EnablePgSearchAndCreateBm25Index < ActiveRecord::Migration[8.1]
  def up
    execute "CREATE EXTENSION IF NOT EXISTS pg_search"
    execute <<~SQL
      CREATE INDEX idx_knowledge_records_bm25
      ON knowledge_records
      USING bm25 (id, title, summary, content, tags)
      WITH (key_field='id')
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS idx_knowledge_records_bm25"
    execute "DROP EXTENSION IF EXISTS pg_search"
  end
end
