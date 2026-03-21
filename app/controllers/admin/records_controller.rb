module Admin
  class RecordsController < BaseController
    def index
      @records = KnowledgeRecord.all

      if params[:q].present?
        @records = @records.bm25_search(params[:q])
      else
        @records = @records.order(updated_at: :desc)
      end

      @records = @records.filter_by_project(params[:project]) if params[:project].present?
      @records = @records.filter_by_knowledge_type(params[:type]) if params[:type].present?
      @records = @records.filter_by_classification(params[:classification]) if params[:classification].present?

      @total = @records.count
      @page = [ params.fetch(:page, 1).to_i, 1 ].max
      @per = 50
      @records = @records.offset((@page - 1) * @per).limit(@per)

      @projects = KnowledgeRecord.distinct.pluck(:project).sort
      @types = KnowledgeRecord::KNOWLEDGE_TYPES
      @classifications = KnowledgeRecord::CLASSIFICATIONS
    end

    def show
      @record = KnowledgeRecord.find_by_shortlink!(params[:id])
    end

    def destroy
      record = KnowledgeRecord.find_by_shortlink!(params[:id])
      record.destroy!
      redirect_to admin_records_path, notice: "Record #{record.shortlink} deleted"
    end
  end
end
