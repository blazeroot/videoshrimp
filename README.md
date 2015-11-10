# Video Sharing Rails App

## What we will create in this tutorial
Following this tutorial you will learn how to create basic video sharing application using rails.

#### Requirements
Some knowledge about RoR, CoffeeScript and HAML. Installed `ffmpeg` and `redis` on development machine.

## Setting up basic elements
Let's create new rails application:
```bash
rails new VideoShrimp
```
When we have our rails app generated, let's add gems that we will use to `Gemfile`.
```ruby
gem 'haml'
gem 'devise'
gem 'simple_form'
gem 'paperclip'
gem 'bootstrap-sass'
gem 'sidekiq'
gem 'sidetiq', github: 'sfroehler/sidetiq', branch: 'celluloid-0-17-compatibility'
gem 'pubnub',  github: 'pubnub/ruby', branch: 'celluloid'
gem 'sinatra', :require => nil

group :development do
  gem 'pry'
  gem 'pry-rails'
end
```
And some explanation:
* **haml** - We'll use haml for templates. Much better than classical `*.html.erb`.
* **devise** - We do want to have authorization on VideoShrimp.
* **simple_form** - Another "make life easier" gem.
* **bootstrap-sass** - No need to comment, I guess.
* **sidekiq** - For video processing in background.
* **sidetiq** - For reoccurring jobs.
* **pubnub** - For notifications and some backend-frontend communication.
* **sinatra** - For `sidekiq` frontend, it's optional dependency.
* **pry** - Better `irb`
* **pry-rails** - Loads `pry` insted of `irb` via `rails c`

**Important note #1:** As you can see, `sidekiq` gem is fetched from other repository than official, it's because official gem isn't compatibilie with newest `celluloid`

**Important note #2:** `pubnub` gem is fetched from different branch than master because it's not yet official stable version. Therefore we will use beta version from `celluloid` branch insted of current master version (celluloid version is refactored and uses celluloid insted of eventmachine).

Let's run standard `bundle` to download added gems.

### Installing devise and simple_form
Devise has to be initialized by command:
```bash
rails generate devise:install
```
SimpleForm has to be inititalized by similar command:
```bash
rails generate simple_form:install --bootstrap
```
We're adding `--bootstrap` flag because, well, we'll use bootstrap.

Now time for models and migrations.

### User model
We're using devise so let's generate user with that:
```bash
rails generate devise user
```
Well, for sake of this tutorial we don't need anything else here yet.

### Video model
We're generating Video model with command:
```bash
rails generate model Video name:string video_file:attachment mp4_file:attachment webm_file:attachment ogg_file:attachment thumbnail:attachment published:boolean likes:integer user:references
```

That migration needs one additional thing - *likes* default value of *0*. Your migration should look like that:
```ruby
class CreateVideos < ActiveRecord::Migration
  def change
    create_table :videos do |t|
      t.string :name
      t.attachment :video_file
      t.attachment :mp4_file
      t.attachment :webm_file
      t.attachment :ogg_file
      t.attachment :thumbnail
      t.boolean :published
      t.integer :likes, default: 0
      t.references :user, index: true, foreign_key: true

      t.timestamps null: false
    end
  end
end
```

Now model code. 

```ruby
class Video < ActiveRecord::Base
  belongs_to :user

  has_attached_file :video_file
  has_attached_file :mp4_file
  has_attached_file :webm_file
  has_attached_file :ogg_file
  has_attached_file :thumbnail, styles: { medium_nr: "250x150!" }

  validates_attachment_content_type :video_file, content_type: /\Avideo/
  validates_attachment_content_type :mp4_file, content_type: /.*/
  validates_attachment_content_type :webm_file, content_type: /.*/
  validates_attachment_content_type :ogg_file, content_type: /.*/

  validates_attachment_presence :video_file

  def publish!
    self.published = true
    save
  end

  def like!
    self.likes += 1
    save
  end

  def dislike!
    self.likes -= 1
    save
  end

  def all_formats_encoded?
    self.webm_file.path && self.mp4_file.path && self.ogg_file.path ? true : false
  end
end
```

The code is self-explanatory so I won't bother you with more comments here.
User model needs to be updated because of relation with Video:

```ruby
class User < ActiveRecord::Base
  has_many :videos
  
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable
end
```

### Running migrations
Great, so we have our models coded and migrations ready to migrate, let's do this.
```bash
rake db:migrate
```

### Controllers and views
Now, let's create controllers and views for VideoShrimp. We should allow users to create account and sign in.

First thing we have to do is to generate devise views and convert them to haml.
```bash
rails generate devise:views
```
and remove `*.html.erb` ones
```bash
rm app/views/devise/**/*.erb
```

We will add separate clean layout for devise. Starting form `application_controller.rb` let's define layout:

```ruby
class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
  layout :layout_by_resource

  protected

  def layout_by_resource
    if devise_controller?
      'devise'
    else
      'application'
    end
  end
end
```

Now the `app/views/layouts/devise.haml`
```haml
!!!
%html
  %head
    %title VideoShrimp
    = stylesheet_link_tag    'application', media: 'all', 'data-turbolinks-track' => true
    = javascript_include_tag 'application', 'data-turbolinks-track' => true
    = csrf_meta_tags
  %body{'data-no-turbolink': true}
    .row
      .col-md-4.col-md-offset-4
        = yield
```

Great. Now let's create `users_controller.rb` under `app/controllers`
```ruby
class UsersController < ApplicationController
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
```
That's quite really basic user controller that will allow us to display user profile and user to change his email.

We need videos controller too!
```ruby
class VideosController < ApplicationController
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
    @video.like!
  end

  def dislike
    @video.dislike!
  end

  private

  def video_params
    params.require(:video).permit(:name, :video_file)
  end
end
```
Quite straightforward, isn't it?

Now views again. Let's remove `application.html.erb` layout from `app/views/layouts`  and create `application.haml`.

```haml
!!!
%html
  %head
    %title VideoShrimp
    = stylesheet_link_tag    'application', media: 'all', 'data-turbolinks-track' => true
    = stylesheet_link_tag    '//vjs.zencdn.net/5.0.2/video-js.css'
    = javascript_include_tag 'application', 'data-turbolinks-track' => true
    = javascript_include_tag '//cdn.pubnub.com/pubnub-dev.js'
    = csrf_meta_tags
  %body{'data-no-turbolink': true}
    - if current_user
      .navbar.navbar-default.navbar-fixed-top
        .container
          .navbar-header
            = link_to 'VideoShrimp', root_url, class: 'navbar-brand'
          %ul.nav.navbar-nav.navbar-right
            %li
              = link_to 'Browse videos', videos_path
            %li
              = link_to 'Upload video', new_video_path
            %li.dropdown
              %a.dropdown-toggle{"aria-expanded" => "false", "aria-haspopup" => "true", "data-toggle" => "dropdown", :href => "#", :role => "button"}
                = current_user.email
                %span.caret
              %ul.dropdown-menu
                %li
                  = link_to 'Profile', current_user
                %li
                  = link_to 'Edit profile', edit_user_path(current_user)
                %li.divider{:role => "separator"}
                %li
                  = link_to 'Log out', destroy_user_session_path, :method => :delete
    = yield
 ```
That's empty layout with some basic bootstrapped top navigation. There're also tags for *pubnub* that we will use and *videojs*.

Let's add bootstrap to stylesheets! Edit `app/assets/stylesheets/application.scss` to look like:
```scss
@import "bootstrap-sprockets";
@import "bootstrap";
@import "global";
@import "video";
```
Bootstrap needs to be added to javascript file `app/assets/javascripts/applications.js` too! So it should look like:
```javascript
//= require jquery
//= require jquery_ujs
//= require turbolinks
//= require bootstrap
//= require_tree .
```

Last one small thing to do in *assets* is to create `global.scss` file under `app/assets/stylesheets/` and add there:
```scss
body{
  padding-top: 60px;
}
```
Thanks to that content won't hide under top navigation.

All of this stuff will won't work of course because we haven't created routes yet. So let's do it and edit `config/routes.rb` to look like:
```ruby
require 'sidekiq/web'
Rails.application.routes.draw do

  root 'videos#index'
  resources :videos

  get '/videos/:id/like' => 'videos#like'
  get '/videos/:id/dislike' => 'videos#dislike'

  devise_for :users

  resources :users

  mount Sidekiq::Web => '/sidekiq'
end
```
So, *home page* of our application will be list of uploaded videos. Making resources for *videos* and *users* is a bit overkill because we won't be using part of routes that are created thanks to that but if you would like to expand application that we're creating you will defienetely need it.
Sidekiq web it's just web interface for *sidekiq* - just nice stuff to have.

At least the rest of views, some form etc.

Let's start with user. Under `app/views/users/` let's create two files:
`show.haml`
```haml
.container
  .row.video-full{ 'data-video-id': @video.id }
    .col-md-10
      %h1= @video.name
      %p.small
        = link_to 'Back to videos' ,videos_path

      - if @video.all_formats_encoded?
        %video#my-video.video-js{:controls => "", "data-setup" => "{}", :height => "264", :preload => "auto", :width => "640"}
          %source{:src => @video.mp4_file.url, :type => "video/mp4"}
          %source{:src => @video.webm_file.url, :type => "video/webm"}
          %source{:src => @video.ogg_file.url, :type => "video/ogg"}
          %p.vjs-no-js
            To view this video please enable JavaScript, and consider upgrading to a web browser that
            %a{:href => "http://videojs.com/html5-video-support/", :target => "_blank"} supports HTML5 video
      - else
        %p Video is still being encoded.
    .col-md-2
      %h1
        %span.likes-count= @video.likes
        %span.glyphicon.glyphicon-heart
    .col-md-12
      %hr
      = link_to 'Like', video_like_path(@video), class: 'btn btn-success', remote: true
      = link_to 'Dislike', video_dislike_path(@video), class: 'btn btn-danger', remote: true
```
Yes, that's user profile. Yes, there is not a lot of things.

`edit.haml`
```haml
.container
  .row
    .col-md-6.col-sm-12
      %h2 Edit profile

      = simple_form_for @user do |f|
        = f.input :email
        = f.button :submit, class: 'btn-primary', value: 'Update Profile'
```

Now let's create video views, put them in `app/views/videos`
`index.haml`
```haml
.container
  .row
    - @videos.each do |video|
      .col-md-3.thumb.video-thumb{ 'data-video-id': video.id }
        .likes
          %span.likes-count= video.likes
          %span.glyphicon.glyphicon-heart
        = link_to video, class: 'thumbnail' do
          = image_tag video.thumbnail.url(:medium_nr)
  .row
    .col-md-12
      .pull-right
        = link_to 'Upload new video', new_video_url, class: 'btn btn-primary'
```
It will render list of videos' thumbnails, three in a row. Every thumbnail has `data-video-id` property that we will use later. There's also likes counter on each video.


`show.haml`
```ruby
.container
  .row.video-full{ 'data-video-id': @video.id }
    .col-md-10
      %h1= @video.name
      %p.small
        = link_to 'Back to videos' ,videos_path

      - if @video.all_formats_encoded?
        %video#my-video.video-js{:controls => "", "data-setup" => "{}", :height => "264", :preload => "auto", :width => "640"}
          %source{:src => @video.mp4_file.url, :type => "video/mp4"}
          %source{:src => @video.webm_file.url, :type => "video/webm"}
          %source{:src => @video.ogg_file.url, :type => "video/ogg"}
          %p.vjs-no-js
            To view this video please enable JavaScript, and consider upgrading to a web browser that
            %a{:href => "http://videojs.com/html5-video-support/", :target => "_blank"} supports HTML5 video
      - else
        %p Video is still being encoded.
    .col-md-2
      %h1
        %span.likes-count= @video.likes
        %span.glyphicon.glyphicon-heart
```
Displays video and allows us to like or dislike. It doesn't update counter because we will be using pubnub notifications to do that. Anyway, in non-POC application optimistic likes update would be good thing to do here.


`new.haml`
```haml
.container
  .row
    .col-md-6.col-sm-12
      %h2 Upload new video

      = simple_form_for @video, html: { multipart: true } do |f|
        = f.input :name
        = f.input :video_file, as: :file
        = f.button :submit, class: 'btn-primary', value: 'Upload Video'
```
Simple form to upload video. Give it a name and pass a file.

Congratulations! You have done some stuff!

## Video encoding and notifications

So, now we need to encode uploaded videos, show them to user and send notifications. Let's setup pubnub to do that.

> HERE HOW TO REGISTER ON PUBNUB, GENERATE KEYS, ENABLE WILDCARD CHANNELS AND PAM.

Now we need to add `pubnub.rb` under `config/initializers`

```ruby
$pubnub = Pubnub.new(
    subscribe_key: Rails.application.secrets.pubnub_subscribe_key,
    publish_key: Rails.application.secrets.pubnub_publish_key,
    secret_key: Rails.application.secrets.pubnub_secret_key,
    auth_key: Rails.application.secrets.pubnub_auth_key
)

$pubnub.grant(
    read: true,
    write: false,
    auth_key: nil,
    channel: 'video.*',
    http_sync: true,
    ttl: 0
)

$pubnub.grant(
    read: true,
    write: true,
    auth_key: Rails.application.secrets.pubnub_auth_key,
    channel: 'video.*',
    http_sync: true,
    ttl: 0
)

$pubnub.grant(
    read: true,
    write: true,
    auth_key: Rails.application.secrets.pubnub_auth_key,
    channel: 'notifications.*',
    http_sync: true,
    ttl: 0
)
```
As you can see, after initializing `$pubnub` global variable we're running two grants.

First one grants read right for everyone to wildcard channel `video.*`. On channel `video.#{video.id}` we will push updates about video so we will se changes live on webpage.

Second grant grants read and write rights just for backend client to wildcard channel `notifications.*`.  On channels `notifications.#{user.id}` we will send private notifications for users.

**Important notice:** You would like probably to store your auth info in separate file and have different keys for different envirorments, but that tutorial is basic POC so I don't want to complicate stuff.

Next, we have to give user possibility to read from his personal notifications channel. We will do that by creating unique *auth_key* for every user and grants him read right to his notification channel. Let's generate migration:
```bash
rails generate migration add_pn_auth_key_to_users
```
Edit created migration to look like:
```ruby
class AddPnAuthKeyToUsers < ActiveRecord::Migration
  def change
    add_column :users, :pn_auth_key, :string
  end
end
```

Now, edit `user.rb` model and add after `has_many :videos`:
```ruby
after_create :gen_auth_and_grant_perms

def notification_channel
  "notifications.#{self.id}"
end

private

def generate_pn_auth
  self.pn_auth_key = SecureRandom.hex
end

def generate_pn_auth!
  self.generate_pn_auth
  save
end

def gen_auth_and_grant_perms
  generate_pn_auth!
  $pubnub.grant(
    channel: notification_channel,
    auth_key: pn_auth_key,
    ttl: 0,
    http_sync: true
  )
end
```
That will run `gen_auth_and_grant_perms` method after user is created. User will get his unique *auth_key* and right to read on his private channel.

Now we will update `Video` model. Edit `video.rb` and make changes in `publish!` `like!` and `dislike!` methods.
```ruby
def publish!
  self.published = true
  save
  $pubnub.publish(channel: "video.#{id}", message: {event: :published}, http_sync: true)
  $pubnub.publish(channel: self.user.notification_channel, message: {event: :published, scope: :videos, id: self.id, name: name.truncate(20)}, http_sync: true)
end

def like!
  self.likes += 1
  save
  $pubnub.publish(channel: "video.#{id}", message: {event: :liked}, http_sync: true)
end

def dislike!
  self.likes -= 1
  save
  $pubnub.publish(channel: "video.#{id}", message: {event: :disliked}, http_sync: true)
end
```

Great!  Now every like and dislike sends message to liked/disliked video channel so we can update our frontend.

Before working on frontend we need to write workers that will encode freshly uploaded video. Let's create `app/workers` directory. Inside it we need to create several files:

`mp4_video_encoder.rb`
```ruby
class Mp4VideoEncoder
  include Sidekiq::Worker

  def perform(video_id)
    video = Video.find(video_id)
    path = video.video_file.path
    output = "/tmp/#{Time.now.getutc.to_f.to_s.delete('.')}.mp4"
    _command = `ffmpeg -i #{path} -f mp4 -vcodec h264 -acodec aac -strict -2 #{output}`
    if $?.to_i == 0
      video.mp4_file = File.open(output, 'r')
      video.save
      FileUtils.rm(output)
    else
      raise $?
    end
  end
end
```

As you can see it's simple script which retrieves video from db by it's *id*, generates random output path and runs shell command to encode orginal uploaded file into mp4 format. If shell command finished with success video is updated with new file, saved and temporary file produced by ffmpeg deleted.

Two next files are almost the same, if you want be more DRY you can write own module that encodes given video to given format and include that module in workers to use. Anyway, two next files:

`ogv_video_encoder.rb`
```ruby
class OgvVideoEncoder
  include Sidekiq::Worker

  def perform(video_id)
    video = Video.find(video_id)
    path = video.video_file.path
    output = "/tmp/#{Time.now.getutc.to_f.to_s.delete('.')}.ogv"
    _command = `ffmpeg -i #{path} -codec:v libtheora -qscale:v 7 -codec:a libvorbis -qscale:a 7 #{output}`
    if $?.to_i == 0
      video.ogg_file = File.open(output, 'r')
      video.save
      FileUtils.rm(output)
    else
      raise $?
    end
  end
end
```

and `webm_video_encoder.rb`
```ruby
class WebmVideoEncoder
  include Sidekiq::Worker

  def perform(video_id)
    video = Video.find(video_id)
    path = video.video_file.path
    output = "/tmp/#{Time.now.getutc.to_f.to_s.delete('.')}.webm"
    _command = `ffmpeg -i #{path} -f webm -c:v libvpx -b:v 1M -c:a libvorbis #{output}`
    if $?.to_i == 0
      video.webm_file = File.open(output, 'r')
      video.save
      FileUtils.rm(output)
    else
      raise $?
    end
  end

end
```

The third one file will take one frame at `00:01:00` time of video and save as video thumbnail.

`thumbnail_cutter.rb`
```ruby
class ThumbnailCutter
  include Sidekiq::Worker

  def perform(video_id)
    video = Video.find(video_id)
    output = "/tmp/#{Time.now.getutc.to_f.to_s.delete('.')}.png"
    _command = `ffmpeg -i #{video.video_file.path} -ss 00:00:01.000 -vframes 1 #{output}`
    if $?.to_i == 0
      video.thumbnail = File.open(output, 'r')
      video.save
      FileUtils.rm(output)
    else
      raise $?
    end
  end
end
```

Great! From here you need to fire *sidekiq* together with rails server. You can do it by typing `bundle exec sidekiq` in console.

When we have workers we would like to fire that workers immedetely after video upload so let's edit our `Video` model and add:

```ruby
after_create :run_encoders

def run_encoders
  ThumbnailCutter.perform_async(self.id)
  Mp4VideoEncoder.perform_async(self.id)
  OgvVideoEncoder.perform_async(self.id)
  WebmVideoEncoder.perform_async(self.id)
end
```

There's still one thing missing. Uploaded video still isn't published! Now we will create reoccurring worker that will search for any non-published video and check if it's ready to be published. If yes, it will publish it and send notification. Create `app/workers/video_publisher.rb` with:
```ruby
class VideoPublisher
  include Sidekiq::Worker
  include Sidetiq::Schedulable

  recurrence { minutely }

  def perform
    Video.where(published: false).each do |video|
      video.publish! if video.all_formats_encoded?
    end
  end
end
```
As you can see, there's little difference between this and previous workers.
`include Sidetiq::Schedulable` - makes that worker, well, schedulable.
`reccurence { minutely }` - makes that worker run every minute.

### Notifications on frontend
Create two files in `app/assets/javascripts/`:

`notifications.js.coffee.erb`
```coffeescript
$ ->
  if $("#user-notifications").length

    auth_key = $("#user-notifications").attr("data-pn-auth-key")
    notification_channel = $("#user-notifications").attr('data-pn-notification-channel')

    add_notifications = (msg) ->
          for notification in msg[0]
              switch notification.event
                  when 'published'
                      notification_html  = "<li><a href='/" + notification.scope + "/" + notification.id + "'>"
                      notification_html += "Your video " + notification.name + " has been published"
                      notification_html += "</a></li>"
                      $("#user-notifications .dropdown-menu").prepend notification_html

    window.pubnub = PUBNUB.init
          subscribe_key: "<%= Rails.application.secrets.pubnub_subscribe_key %>",
          publish_key: "<%= Rails.application.secrets.pubnub_publish_key %>",
          auth_key: auth_key

    window.pubnub.history
        channel: notification_channel,
        count: 10,
        reverse: false,
        callback: (msg) ->
            add_notifications(msg)

    window.pubnub.subscribe
        channel: notification_channel,
        callback: (msg) ->
            add_notifications(msg)

    
```
That script runs after document is loaded and there's `#user-notifications` node in DOM. It initializes *pubnub* client with user auth_key. Loads previous ten notifications form user notifications channel and later subscribes to that channel waiting for new notifications.

And second file:
`videos.coffee`
```coffeescript
$ ->
  for video in $('.video-full, .video-thumb')
    window.pubnub.subscribe
      channel: 'video.' + $(video).attr('data-video-id')
      message: (msg, env, chan) ->
        id = chan.split('.')[1]
        switch msg.event
          when 'published'
            location.reload()
          when 'liked'
            console.log('liked')
            for likes in $("[data-video-id=" + id + "]").find('.likes-count')
              console.log('add')
              $(likes).html(parseInt($(likes).html()) + 1)
          when 'disliked'
            console.log('disliked')
            for likes in $("[data-video-id=" + id + "]").find('.likes-count')
              console.log('remove')
              $(likes).html(parseInt($(likes).html()) - 1)
          else
            console.log(msg)
```
That script subscribes to information channel about every video on page. When user is on video page that isn't published yet, and it receive message about publish, it simply reload webpage. Two other events that can happen is like and dislike. As you can expect it searches for every occurence of video with given in channel name id and updates likes counter.

> SOME THOUGHTFUL EPILOGUE WITH INFORMATION HOW IT CAN BE EXPANDED AND WHAT WAS SIMPLIFIED FOR THAT EXAMPLE
