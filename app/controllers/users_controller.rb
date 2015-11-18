class UsersController < ApplicationController
  # Checks if user is signed in before running controller, functionality provided by devise
  before_action :authenticate_user!

  before_action :set_user, only: [:show]
  before_action :set_current_user, only: [:edit, :update]

  def index
    @users = User.all
  end

  def show
  end

  def update
    respond_to do |format|
      if @user.update(user_params)
        format.html { redirect_to @user, notice: 'User was successfully updated.' }
        format.json { render :show, status: :ok, location: @user }
      else
        format.html { render :edit }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  private
  def set_user
    @user = User.find(params[:id])
  end

  def set_current_user
    @user = current_user
  end

  def user_params
    params.require(:user).permit(:email)
  end
end