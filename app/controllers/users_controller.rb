class UsersController < ApplicationController
  respond_to :js, :html

  before_action :authenticate_user!

  def show
    @user = User.find(params[:id])
  end

  def edit
    @user = current_user
  end

  def update
    user = User.find(params[:id])
    user.update(user_params)
    user.save
    redirect_to user
  end

  private

  def user_params
    params.require(:user).permit(:email)
  end
end
