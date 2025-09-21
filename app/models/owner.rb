class Owner < ApplicationRecord
  belongs_to :host
  has_many :repositories, primary_key: :login, foreign_key: :owner
  has_many :issues, through: :repositories

  scope :visible, -> { where(hidden: false) }
  scope :hidden, -> { where(hidden: true) }

  def to_param
    login
  end

  def hide!
    update!(hidden: true)
  end

  def unhide!
    update!(hidden: false)
  end
end