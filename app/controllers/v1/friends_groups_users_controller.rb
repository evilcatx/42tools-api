class V1::FriendsGroupsUsersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_friends_group
  before_action :set_friends_groups_user, only: [:show, :destroy]

  # GET /friends_groups_users
  def index
    @friends_groups_users = @friends_group.friends_groups_users
  end

  # GET /friends_groups_users/1
  def show
  end

  # POST /friends_groups_users
  def create
    begin
      friend_id = params.require(:user_id)
    rescue ActionController::ParameterMissing => e
      return render json: {
        error: e.message
      }, status: :bad_request
    end

    friends_user = current_user.friends_users.find_by(friend_id: friend_id)
    @friends_groups_user = @friends_group.friends_groups_users.find_or_initialize_by(friends_user: friends_user)
    @friends_groups_user_is_new_record = @friends_groups_user.new_record?

    if @friends_groups_user.save
      render :show, status: @friends_groups_user_is_new_record ? :created : :ok, location: v1_friends_group_friend_url(@friends_group, @friends_groups_user)
    else
      render json: @friends_groups_user.errors, status: :unprocessable_entity
    end
  end

  # DELETE /friends_groups_users/1
  def destroy
    @friends_groups_user.destroy
  end

private

  # Use callbacks to share common setup or constraints between actions.
  def set_friends_group
    @friends_group = current_user.friends_groups.find_by(id: params[:friends_group_id])

    render json: {
      error: 'record not found'
    }, status: :not_found unless @friends_group
  end

  def set_friends_groups_user
    @friends_groups_user = @friends_group.friends_groups_users.joins(:friends_user).find_by(friends_users: { friend_id: params[:id] })

    render json: {
      error: 'record not found'
    }, status: :not_found unless @friends_groups_user
  end
end