# Video Sharing Rails App

## What we will create in this tutorial
Following this tutorial you will learn how to create basic video sharing application prototype using rails. Features list includes:
* Signing up, in and out - we will use `devise` for that.
* Uploading video - Simple upload, we will need to handle encoding for web formats.
* Playing video - we will use basic videojs snippet to create simple video player.
* Notifications - we would like to notify user when encoding is done and create scaffold for notifications system, we will use `pubnub` for that.
* Like counter - simple example how to update page elements dynamically with usage of `pubnub` lib.
#### Requirements
Some knowledge about RoR, CoffeeScript and HAML. Installed `ffmpeg` and `redis` on development machine.

## Setting up basic elements
Let's create new rails application:
```bash
rails new VideoShrimp
```
We won't be focusing on tests here so you can add `-T` flag to skip tests. SQLite will be used in this example but feel free to use postgresql, mysql or anything that you would like.

Please make sure you have installed rails 4.1 or newer. When I'm creating this tutorial I'm using:
```bash
> rails -v
Rails 4.2.4

> ruby -v
ruby 2.2.2p95 (2015-04-13 revision 50295) [x86_64-darwin15]
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
* **haml** - We'll use haml for templates. Much better than classical `*.html.erb` I can reccomend **slim** too. If you want to stick with `html.erb` you will have to write some more code but it's fine.
* **devise** - We do want to have authorization on VideoShrimp and we don't want to spend too much time on it so we will use ready library. We will use just small part of **devise** power but it will speed up a little our development.
* **simple_form** - Another "make life easier" gem. It generates nice forms with less typing.
* **paperclip** - It gem that makes managing attachments easier. To be honest we don't need it in our app but I would like to show some basic functionality of that gem.
* **bootstrap-sass** - No need to comment, I guess.
* **sidekiq** - For video processing in background. It runs as separate process and is nicely scalable.
* **sidetiq** - For reoccurring jobs in `Sidekiq` - you can think about it as `sidekiq` plugin. We will need it to check if there's any unpublished video that is already encoded and publish it.
* **pubnub** - For notifications and some backend-frontend communication. Really easy to use and full of features system.
* **sinatra** - For `sidekiq` frontend, it's optional dependency.
* **pry** - Better `irb`
* **pry-rails** - Loads `pry` insted of `irb` via `rails c`

**Important note #1:** As you can see, `sidekiq` gem is fetched from other repository than official, it's because official gem isn't compatibilie with newest `celluloid` (at least when I'm writing this).

**Important note #2:** `pubnub` gem is fetched from different branch than master because `celluloid` version it's not yet official stable. Therefore we will use beta version from `celluloid` branch insted of current master version (celluloid version is refactored and uses celluloid insted of eventmachine).

Let's run standard `bundle install` to download added gems.
```bash
bundle install
```

### Installing devise and simple_form
SimpleForm has to be initialized by command:
```bash
rails generate simple_form:install --bootstrap
```
We're adding `--bootstrap` flag because, well, we'll use bootstrap. That will generate two initializers, locale file and template file.

Devise has to be inititalized by similar command:
```bash
rails generate devise:install
```
That will generate `config/initializers/devise.rb` and `config/locales/devise.en.yml` you don't need to care about these files right now as we don't need any additional devise configuration for this example.

Let's generate devise views where simple form will be used:
```bash
rails generate devise:views
```

When we have our project set up it's time for models and migrations.

### User model
We're using devise so let's generate user with that:
```bash
> rails generate devise user
      invoke  active_record
      create    db/migrate/20151117181300_devise_create_users.rb
      create    app/models/user.rb
      invoke    test_unit
      create      test/models/user_test.rb
      create      test/fixtures/users.yml
      insert    app/models/user.rb
       route  devise_for :users
```
Well, for this tutorial we don't need anything else here yet. By default user will have unique email and will be signing in using it.

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
  # Association declaration
  belongs_to :user

  # Paperclip attachments declaration
  has_attached_file :video_file
  has_attached_file :mp4_file
  has_attached_file :webm_file
  has_attached_file :ogg_file
  # Styles declaration makes paperclip to use imagemagick to resize image to given size
  has_attached_file :thumbnail, styles: { medium_nr: "250x150!" }

  # Paperclip requires to set attachment validators
  validates_attachment_content_type :video_file, content_type: /\Avideo/
  validates_attachment_content_type :mp4_file, content_type: /.*/
  validates_attachment_content_type :webm_file, content_type: /.*/
  validates_attachment_content_type :ogg_file, content_type: /.*/

  # We want video model always to have :video_file attachment
  validates_attachment_presence :video_file

  # Publish video makes it available
  def publish!
    self.published = true
    save
  end

  # Increment likes counter
  def like!
    self.likes += 1
    save
  end

  # Decrease likes counter
  def dislike!
    self.likes -= 1
    save
  end

  # Checks if all formats are already encoded, the simplest way
  def all_formats_encoded?
    self.webm_file.path && self.mp4_file.path && self.ogg_file.path ? true : false
  end
end
```

The code is self-explanatory so I won't bother you with more comments here.
User model needs to be updated because of relation with Video:

```ruby
class User < ActiveRecord::Base
  # Association declaration 
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

We will add separate clean layout for devise. Starting form `app/controllers/application_controller.rb` let's define layout:

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
We're checking here of current controller is devise controller and return devise if true. If it's other controller (video, user, anything else) we will return standard application layout.


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
    .container
      .row
        .col-md-4.col-md-offset-4
          %h1.text-center VideoShrimp
          = yield
```
In devise layout we need just to include basic stuff. `container`, `row`, `.col-md-4` and `.col-md-offset-4` are bootstrap grid classes. If you don't know them I encourage you to read about [Bootstrap Grid System](http://getbootstrap.com/css/#grid).

Great. Now let's create `users_controller.rb` under `app/controllers`
```ruby
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
```
That's quite really basic user controller that will allow us to display user profile and user to change his email.

We need videos controller too!
```ruby
class VideosController < ApplicationController
  before_action :authenticate_user!
  before_action :set_video, only: [:show, :edit, :like, :dislike]

  # All published videos
  def index
    @videos = Video.where(published: true)
  end

  def show
  end

  def new
    @video = Video.new
  end

  def edit
  end

  def create
    @video = Video.new(video_params)

    respond_to do |format|
      if @video.save
        format.html { redirect_to @video, notice: 'Video was successfully created.' }
        format.json { render :show, status: :created, location: @video }
      else
        format.html { render :new }
        format.json { render json: @video.errors, status: :unprocessable_entity }
      end
    end
  end

  # Likes video, increment likes count
  def like
    @video.like!
  end

  # Dislikes video, increment likes count
  def dislike
    @video.dislike!
  end

  private
  def set_video
    @video = Video.find(params[:id])
  end

  def video_params
    params.require(:video).permit(:video_file, :name)
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

            %li#user-notifications.dropdown{"data-pn-auth-key": current_user.pn_auth_key, "data-pn-notification-channel": current_user.notification_channel}
              %a.dropdown-toggle{"aria-expanded" => "false", "aria-haspopup" => "true", "data-toggle" => "dropdown", :href => "#", :role => "button"}
                %span.glyphicon.glyphicon-bell
              %ul.dropdown-menu

    = yield
 ```
That's empty layout with some basic bootstrapped top navigation. There're also tags for *pubnub* that we will use for notifications and *videojs* for video player.

Let's add bootstrap to stylesheets! 
First, remove `app/assets/stylesheets/application.css` and create `app/assets/stylesheets/application.scss` with:
```scss
@import "bootstrap-sprockets";
@import "bootstrap";
@import "global";
@import "video";
```
Create `global.scss` and `video.scss` too.

Bootstrap needs to be added to javascript file `app/assets/javascripts/applications.js` alos. So it should look like:
```javascript
//= require jquery
//= require jquery_ujs
//= require turbolinks
//= require bootstrap
//= require_tree .
```

Last one small thing to do in *assets* is to edit `global.scss` file under `app/assets/stylesheets/` and add there:
```scss
body {
  padding-top: 60px;
}
```
Thanks to that webpage content won't hide under top navigation.

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
Sidekiq web it's just web interface for *sidekiq* - just nice stuff to have. Don't miss `require 'sidekiq/web'` on top of the file.

At least the rest of views, some form etc.

Let's start with user. Under `app/views/users/` let's create two files:
`show.haml`
```haml
.container
  .row
    .col-md-12
      %h2= @user.email
.container
  .row
    - @user.videos.each do |video|
      .col-md-3.thumb.video-thumb{ 'data-video-id': video.id }
        .likes
          %span.likes-count= video.likes
          %span.glyphicon.glyphicon-heart
        = link_to video, class: 'thumbnail' do
          = image_tag video.thumbnail.url(:medium_nr)
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

Congratulations! You have done some stuff already!

## Video encoding and notifications

So, now we need to encode uploaded videos, show them to user and send notifications. Let's setup pubnub to do that.

Head to [Pubnub website](pubnub.com) and create new account. After creating new account you should add new app and generate keys for these app. We will use [Storeage & Playback](https://www.pubnub.com/products/stream-controller/) feature for notifications history and [Access Manager](https://www.pubnub.com/products/access-manager/) to make private notifications private.

You will need to copy your keys to `config/secrets.yml` as `pubnub_subscribe_key`, `pubnub_publish_key`, `pubnub_secret_key` and you should create by yourself some unique `pubnub_auth_key` for server.

Now we need to add `pubnub.rb` under `config/initializers`, that code will run while application is starting.

`pubnub.rb`
```ruby
# Initialize pubnub client with our keys
$pubnub = Pubnub.new(
    subscribe_key: Rails.application.secrets.pubnub_subscribe_key,
    publish_key: Rails.application.secrets.pubnub_publish_key,
    secret_key: Rails.application.secrets.pubnub_secret_key,
    auth_key: Rails.application.secrets.pubnub_auth_key
)

# As we have PAM enabled, we have to grant access to channels.
# That grants read right to any channel that begins with 'video.' to everyone.
$pubnub.grant(
    read: true,
    write: false,
    auth_key: nil,
    channel: 'video.*',
    http_sync: true,
    ttl: 0
)

# That grants read and write right to any channel that begins with 'video.' to this client.
$pubnub.grant(
    read: true,
    write: true,
    auth_key: Rails.application.secrets.pubnub_auth_key,
    channel: 'video.*',
    http_sync: true,
    ttl: 0
)

# That grants read and write right to any channel that begins with 'notifications.' to this client.
$pubnub.grant(
    read: true,
    write: true,
    auth_key: Rails.application.secrets.pubnub_auth_key,
    channel: 'notifications.*',
    http_sync: true,
    ttl: 0
)
```
As you can see, after initializing `$pubnub` global variable we're running three grants with `ttl: 0` - which indicates that the grant will never expire.

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

Now, edit `user.rb` model and add after `devise`:
```ruby
after_create :gen_auth_and_grant_perms

def notification_channel
  "notifications.#{self.id}"
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

def generate_pn_auth
  self.pn_auth_key = SecureRandom.hex
end

def generate_pn_auth!
  self.generate_pn_auth
  save
end
```
That will run `gen_auth_and_grant_perms` method after user is created. User will receive his unique *auth_key*  that will be used by javascript client and access to read on his private channel.

Now we will update `Video` model. Edit `video.rb` and make changes in `publish!` `like!` and `dislike!` methods.
```ruby
# Publish video makes it available
def publish!
  self.published = true
  save
  $pubnub.publish(channel: "video.#{id}", message: {event: :published}, http_sync: true)
  $pubnub.publish(channel: self.user.notification_channel, message: {event: :published, scope: :videos, id: self.id, name: name.truncate(20)}, http_sync: true)
end

# Increment likes counter
def like!
  self.likes += 1
  save
  $pubnub.publish(channel: "video.#{id}", message: {event: :liked}, http_sync: true)
end

# Decrease likes counter
def dislike!
  self.likes -= 1
  save
  $pubnub.publish(channel: "video.#{id}", message: {event: :disliked}, http_sync: true)
end
```

Great!  Now every like and dislike sends message to corresponding video channel so we can live update our frontend when subscribed to given channel. `publish!` will send notification to owner and notification that video has been published on corresponding video channel.

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

As you can see it's simple script which retrieves video from db by it's *id*, generates random output path and runs shell command to encode original file into mp4 format. If shell command finished with success video is updated with new file, saved and temporary file produced by ffmpeg is deleted.

Two next files are almost the same, if you want be more DRY you can write own module that encodes passed video to passed format and include that module in workers to use. Anyway, two next files:

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

When we have workers we would like to fire that workers immediately after video is uploaded so let's edit our `Video` model and add:

```ruby
after_create :run_encoders

private

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
As you can see, there's some difference between this and previous workers.
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
            for likes in $("[data-video-id=" + id + "]").find('.likes-count')
              console.log('add')
              $(likes).html(parseInt($(likes).html()) + 1)
          when 'disliked'
            for likes in $("[data-video-id=" + id + "]").find('.likes-count')
              console.log('remove')
              $(likes).html(parseInt($(likes).html()) - 1)
```
That script subscribes to information channel about every video on page (We have two type of elements with videos. One has class `video-full` and second has class `video-thumb`, both of them have`data-video-id` that is used to determine channel name to subscribe). When user is on video page that isn't published yet, he is subscribed to that non-published video channel, and when client receive message about video beeing published, it simply reload webpage. Two other events that can happen is like and dislike. As you can expect it searches for every occurence of video with given in channel name id and updates likes counter.

So, let's take a look at out application. When you fire rails server and sidekiq, you can head to `localhost:3000`. You will be welcome by sign in form. Let's choose sign up and create some new user. That's it! Feel free to play around your new prototype.

That's it. You've made video sharing app prototype. There's a lot stuff that can be added or changed here. For example loading more notification, marking point in time when user viewed notifications. Nicer video uploader. You can limit likes (one like per video per user). Add comments section that will be updated live thanks to pubnub. Or ever rewrite whole frontend to SPA, make own API for communication or push data thought Pubnub.
