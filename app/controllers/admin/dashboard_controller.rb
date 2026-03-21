module Admin
  class DashboardController < BaseController
    def show
      @total_records = KnowledgeRecord.count
      @by_project = KnowledgeRecord.group(:project).count.sort_by { |_, v| -v }
      @by_type = KnowledgeRecord.group(:knowledge_type).count
      @by_classification = KnowledgeRecord.group(:classification).count
      @recent = KnowledgeRecord.order(created_at: :desc).limit(20)
      @oldest = KnowledgeRecord.order(updated_at: :asc).limit(5)
      @db_size = ActiveRecord::Base.connection.execute(
        "SELECT pg_size_pretty(pg_database_size(current_database())) AS size"
      ).first["size"]
    end
  end
end
