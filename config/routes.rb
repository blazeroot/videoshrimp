Rails.application.routes.draw do

  root 'videos#index'
  resources :videos

  get '/videos/:id/like' => 'videos#like', as: :video_like
  get '/videos/:id/dislike' => 'videos#dislike', as: :video_dislike

  devise_for :users

  resources :users

  require 'sidekiq/web'
  mount Sidekiq::Web => '/sidekiq'
end
