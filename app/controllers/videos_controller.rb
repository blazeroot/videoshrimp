class VideosController < ApplicationController
  respond_to :js, :html

  before_action :authenticate_user!

  def create
    @video = Video.new(video_params)
    @video.user = current_user
    if @video.save
      respond_with @video
    else
      render json: @video.errors
    end
  end

  def index
    @videos = Video.where(published: true)
  end

  def show
    @video = Video.find(params[:id])
  end

  def new
    @video = Video.new
  end

  def like
    @video = Video.find(params[:id])
    @video.like!
    render json: @video.likes
  end

  def dislike
    @video = Video.find(params[:id])
    @video.dislike!
    render json: @video.likes
  end

  private

  def video_params
    params.require(:video).permit(:name, :video_file)
  end
end
