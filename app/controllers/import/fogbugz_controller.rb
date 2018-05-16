class Import::FogbugzController < Import::BaseController
  before_action :verify_fogbugz_import_enabled
  before_action :user_map, only: [:new_user_map, :create_user_map]

  rescue_from Fogbugz::AuthenticationException, with: :fogbugz_unauthorized

  def new
  end

  def callback
    begin
      res = Gitlab::FogbugzImport::Client.new(import_params.symbolize_keys)
    rescue
      # If the URI is invalid various errors can occur
      return redirect_to new_import_fogbugz_path, alert: '无法连接 FogBugz，请检查你的链接'
    end
    session[:fogbugz_token] = res.get_token
    session[:fogbugz_uri] = params[:uri]

    redirect_to new_user_map_import_fogbugz_path
  end

  def new_user_map
  end

  def create_user_map
    user_map = params[:users]

    unless user_map.is_a?(Hash) && user_map.all? { |k, v| !v[:name].blank? }
      flash.now[:alert] = '所有用户必须有一个名字。'

      return render 'new_user_map'
    end

    session[:fogbugz_user_map] = user_map

    flash[:notice] = '用户映射已保存。请选择要导入的项目继续。'

    redirect_to status_import_fogbugz_path
  end

  def status
    unless client.valid?
      return redirect_to new_import_fogbugz_path
    end

    @repos = client.repos

    @already_added_projects = find_already_added_projects('fogbugz')
    already_added_projects_names = @already_added_projects.pluck(:import_source)

    @repos.reject! { |repo| already_added_projects_names.include? repo.name }
  end

  def jobs
    render json: find_jobs('fogbugz')
  end

  def create
    repo = client.repo(params[:repo_id])
    fb_session = { uri: session[:fogbugz_uri], token: session[:fogbugz_token] }
    umap = session[:fogbugz_user_map] || client.user_map

    project = Gitlab::FogbugzImport::ProjectCreator.new(repo, fb_session, current_user.namespace, current_user, umap).execute

    if project.persisted?
      render json: ProjectSerializer.new.represent(project)
    else
      render json: { errors: project.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def client
    @client ||= Gitlab::FogbugzImport::Client.new(token: session[:fogbugz_token], uri: session[:fogbugz_uri])
  end

  def user_map
    @user_map ||= begin
      user_map = client.user_map

      stored_user_map = session[:fogbugz_user_map]
      user_map.update(stored_user_map) if stored_user_map

      user_map
    end
  end

  def fogbugz_unauthorized(exception)
    redirect_to new_import_fogbugz_path, alert: exception.message
  end

  def import_params
    params.permit(:uri, :email, :password)
  end

  def verify_fogbugz_import_enabled
    render_404 unless fogbugz_import_enabled?
  end
end
