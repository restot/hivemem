class KnowledgeRecord < ApplicationRecord
  KNOWLEDGE_TYPES = %w[convention pattern decision failure reference guide].freeze
  CLASSIFICATIONS = %w[foundational tactical observational].freeze
  SHORTLINK_LENGTH = 7
  SHORTLINK_ALPHABET = ("a".."z").to_a + ("A".."Z").to_a + ("0".."9").to_a

  validates :title, presence: true
  validates :content, presence: true
  validates :project, presence: true
  validates :knowledge_type, presence: true, inclusion: { in: KNOWLEDGE_TYPES }
  validates :classification, presence: true, inclusion: { in: CLASSIFICATIONS }
  validates :shortlink, presence: true, uniqueness: true

  before_validation :generate_shortlink, on: :create
  before_validation :set_default_classification, on: :create

  # --- Search ---

  scope :bm25_search, ->(query) {
    where("knowledge_records @@@ paradedb.parse(?)", query)
      .select("knowledge_records.*, paradedb.score(knowledge_records.id) AS bm25_score")
      .order(Arel.sql("bm25_score DESC"))
  }

  scope :filter_by_project, ->(project) { where(project: project) if project.present? }
  scope :filter_by_knowledge_type, ->(type) { where(knowledge_type: type) if type.present? }
  scope :filter_by_classification, ->(cls) { where(classification: cls) if cls.present? }
  scope :filter_by_tags, ->(tags) {
    return all if tags.blank?

    Array(tags).reduce(all) { |scope, tag| scope.where("? = ANY(tags)", tag) }
  }

  scope :browse, -> { order(updated_at: :desc) }

  # --- Shortlink generation ---

  def self.find_by_shortlink!(shortlink)
    find_by!(shortlink: shortlink)
  end

  # --- Tag operations ---

  def add_tags(new_tags)
    self.tags = (tags + Array(new_tags)).uniq
    save!
  end

  def remove_tags(tags_to_remove)
    self.tags = tags - Array(tags_to_remove)
    save!
  end

  # --- Relationship operations ---

  def add_relation(target_shortlink)
    self.relates_to = (relates_to + [target_shortlink]).uniq
    save!
  end

  def supersede(target_shortlink)
    self.supersedes = (self.supersedes + [target_shortlink]).uniq
    save!
  end

  def add_outcome(outcome_hash)
    outcome_hash["recorded_at"] ||= Time.current.iso8601
    self.outcomes = outcomes + [outcome_hash]
    save!
  end

  # --- Search result formatting ---

  def as_search_result
    {
      shortlink: shortlink,
      title: title,
      summary: summary,
      tags: tags,
      knowledge_type: knowledge_type,
      classification: classification,
      project: project,
      evidence: evidence,
      score: respond_to?(:bm25_score) ? bm25_score : nil
    }
  end

  def as_full_record
    {
      shortlink: shortlink,
      title: title,
      summary: summary,
      content: content,
      knowledge_type: knowledge_type,
      classification: classification,
      project: project,
      tags: tags,
      evidence: evidence,
      relates_to: relates_to,
      supersedes: supersedes,
      outcomes: outcomes,
      metadata: metadata,
      created_by: created_by,
      created_at: created_at.iso8601,
      updated_at: updated_at.iso8601
    }
  end

  private

  def generate_shortlink
    return if shortlink.present?

    loop do
      self.shortlink = "hm-#{random_base62(SHORTLINK_LENGTH)}"
      break unless self.class.exists?(shortlink: shortlink)
    end
  end

  def set_default_classification
    self.classification ||= "tactical"
  end

  def random_base62(length)
    Array.new(length) { SHORTLINK_ALPHABET.sample }.join
  end
end
