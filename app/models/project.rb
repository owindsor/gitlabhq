require "grit"

class Project < ActiveRecord::Base
  belongs_to :owner, :class_name => "User"

  has_many :users,          :through => :users_projects
  has_many :events,         :dependent => :destroy
  has_many :merge_requests, :dependent => :destroy
  has_many :issues,         :dependent => :destroy, :order => "position"
  has_many :users_projects, :dependent => :destroy
  has_many :notes,          :dependent => :destroy
  has_many :snippets,       :dependent => :destroy
  has_many :deploy_keys,    :dependent => :destroy, :foreign_key => "project_id", :class_name => "Key"
  has_many :web_hooks,      :dependent => :destroy
  has_many :wikis,          :dependent => :destroy
  has_many :protected_branches, :dependent => :destroy

  validates :name,
            :uniqueness => true,
            :presence => true,
            :length   => { :within => 0..255 }

  validates :path,
            :uniqueness => true,
            :presence => true,
            :format => { :with => /^[a-zA-Z0-9_\-\.]*$/,
                         :message => "only letters, digits & '_' '-' '.' allowed" },
            :length   => { :within => 0..255 }

  validates :description,
            :length   => { :within => 0..2000 }

  validates :code,
            :presence => true,
            :uniqueness => true,
            :format => { :with => /^[a-zA-Z0-9_\-\.]*$/,
                         :message => "only letters, digits & '_' '-' '.' allowed"  },
            :length   => { :within => 3..255 }

  validates :owner, :presence => true
  validate :check_limit
  validate :repo_name

  attr_protected :private_flag, :owner_id

  scope :public_only, where(:private_flag => false)
  scope :without_user, lambda { |user|  where("id not in (:ids)", :ids => user.projects.map(&:id) ) }

  def self.active
    joins(:issues, :notes, :merge_requests).order("issues.created_at, notes.created_at, merge_requests.created_at DESC")
  end

  def self.access_options
    UsersProject.access_roles
  end

  def repository
    @repository ||= Repository.new(self)
  end

  delegate :repo,
    :url_to_repo,
    :path_to_repo,
    :update_repository,
    :destroy_repository,
    :tags,
    :repo_exists?,
    :commit,
    :commits,
    :commits_with_refs,
    :tree,
    :heads,
    :commits_since,
    :fresh_commits,
    :commits_between,
    :to => :repository, :prefix => nil

  def to_param
    code
  end

  def web_url
    [GIT_HOST['host'], code].join("/")
  end

  def observe_push(oldrev, newrev, ref, author_key_id)
    data = web_hook_data(oldrev, newrev, ref, author_key_id)

    Event.create(
      :project => self,
      :action => Event::Pushed,
      :data => data
    )
  end

  def execute_web_hooks(oldrev, newrev, ref, author_key_id)
    ref_parts = ref.split('/')

    # Return if this is not a push to a branch (e.g. new commits)
    return if ref_parts[1] !~ /heads/ || oldrev == "00000000000000000000000000000000"

    data = web_hook_data(oldrev, newrev, ref, author_key_id)

    web_hooks.each { |web_hook| web_hook.execute(data) }
  end

  def web_hook_data(oldrev, newrev, ref, author_key_id)
    key = Key.find_by_identifier(author_key_id)
    data = {
      before: oldrev,
      after: newrev,
      ref: ref,
      user_id: key.user.id,
      user_name: key.user_name,
      repository: {
        name: name,
        url: web_url,
        description: description,
        homepage: web_url,
        private: private?
      },
      commits: []
    }

    commits_between(oldrev, newrev).each do |commit|
      data[:commits] << {
        id: commit.id,
        message: commit.safe_message,
        timestamp: commit.date.xmlschema,
        url: "http://#{GIT_HOST['host']}/#{code}/commits/#{commit.id}",
        author: {
          name: commit.author_name,
          email: commit.author_email
        }
      }
    end

    data
  end

  def open_branches
    if protected_branches.empty?
      self.repo.heads
    else
      pnames = protected_branches.map(&:name)
      self.repo.heads.reject { |h| pnames.include?(h.name) }
    end.sort_by(&:name)
  end

  def team_member_by_name_or_email(email = nil, name = nil)
    user = users.where("email like ? or name like ?", email, name).first
    users_projects.find_by_user_id(user.id) if user
  end

  def team_member_by_id(user_id)
    users_projects.find_by_user_id(user_id)
  end

  def common_notes
    notes.where(:noteable_type => ["", nil]).inc_author_project
  end

  def build_commit_note(commit)
    notes.new(:noteable_id => commit.id, :noteable_type => "Commit")
  end

  def commit_notes(commit)
    notes.where(:noteable_id => commit.id, :noteable_type => "Commit", :line_code => nil)
  end

  def commit_line_notes(commit)
    notes.where(:noteable_id => commit.id, :noteable_type => "Commit").where("line_code is not null")
  end

  def has_commits?
    !!commit
  end

  # Compatible with all access rights
  # Should be rewrited for new access rights
  def add_access(user, *access)
    access = if access.include?(:admin) 
               { :project_access => UsersProject::MASTER } 
             elsif access.include?(:write)
               { :project_access => UsersProject::DEVELOPER } 
             else
               { :project_access => UsersProject::REPORTER } 
             end
    opts = { :user => user }
    opts.merge!(access)
    users_projects.create(opts)
  end

  def reset_access(user)
    users_projects.where(:project_id => self.id, :user_id => user.id).destroy if self.id
  end

  def repository_readers
    keys = Key.joins({:user => :users_projects}).
      where("users_projects.project_id = ? AND users_projects.project_access = ?", id, UsersProject::REPORTER)
    keys.map(&:identifier) + deploy_keys.map(&:identifier)
  end

  def repository_writers
    keys = Key.joins({:user => :users_projects}).
      where("users_projects.project_id = ? AND users_projects.project_access = ?", id, UsersProject::DEVELOPER)
    keys.map(&:identifier)
  end

  def repository_masters
    keys = Key.joins({:user => :users_projects}).
      where("users_projects.project_id = ? AND users_projects.project_access = ?", id, UsersProject::MASTER)
    keys.map(&:identifier)
  end

  def readers
    @readers ||= users_projects.includes(:user).map(&:user)
  end

  def writers
    @writers ||= users_projects.includes(:user).map(&:user)
  end

  def admins
    @admins ||= users_projects.includes(:user).where(:project_access => UsersProject::MASTER).map(&:user)
  end

  def allow_read_for?(user)
    !users_projects.where(:user_id => user.id).empty?
  end

  def guest_access_for?(user)
    !users_projects.where(:user_id => user.id).empty?
  end

  def report_access_for?(user)
    !users_projects.where(:user_id => user.id, :project_access => [UsersProject::REPORTER, UsersProject::DEVELOPER, UsersProject::MASTER]).empty?
  end

  def dev_access_for?(user)
    !users_projects.where(:user_id => user.id, :project_access => [UsersProject::DEVELOPER, UsersProject::MASTER]).empty?
  end

  def master_access_for?(user)
    !users_projects.where(:user_id => user.id, :project_access => [UsersProject::MASTER]).empty? || owner_id == user.id
  end

  def root_ref 
    default_branch || "master"
  end

  def public?
    !private_flag
  end

  def private?
    private_flag
  end

  def last_activity
    events.last || nil
  end

  def last_activity_date
    if events.last
      events.last.created_at
    else
      updated_at
    end
  end

  def last_activity_date_cached(expire = 1.hour)
    last_activity_date
  end

  def check_limit
    unless owner.can_create_project?
      errors[:base] << ("Your own projects limit is #{owner.projects_limit}! Please contact administrator to increase it")
    end
  rescue
    errors[:base] << ("Cant check your ability to create project")
  end

  def repo_name
    if path == "gitolite-admin"
      errors.add(:path, " like 'gitolite-admin' is not allowed")
    end
  end

  def valid_repo?
    repo
  rescue
    errors.add(:path, "Invalid repository path")
    false
  end
end
# == Schema Information
#
# Table name: projects
#
#  id                     :integer         not null, primary key
#  name                   :string(255)
#  path                   :string(255)
#  description            :text
#  created_at             :datetime
#  updated_at             :datetime
#  private_flag           :boolean         default(TRUE), not null
#  code                   :string(255)
#  owner_id               :integer
#  default_branch         :string(255)     default("master"), not null
#  issues_enabled         :boolean         default(TRUE), not null
#  wall_enabled           :boolean         default(TRUE), not null
#  merge_requests_enabled :boolean         default(TRUE), not null
#  wiki_enabled           :boolean         default(TRUE), not null
#

