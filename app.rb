# ./app.rb
require "roda"
require "redis"
require "json"
require "open-uri"
require "sequel"
require "newrelic_rpm"

ENV["SITE_URL"] ||= "localhost:3000"
ENV["RACK_ENV"] ||= "development"

if ENV['RACK_ENV'] == 'production'
  DB = Sequel.connect(ENV['DATABASE_URL'])
else
  user = 'root'
  password = 'pass'
  database = 'cat--api'
  DB = Sequel.connect(adapter: "postgres", database: database, host: "127.0.0.1", user: user, password: password)
end

uri = URI.parse(ENV["REDIS_URL"]||"redis://localhost:6379")
$redis = Redis.new(host: uri.host, port: uri.port, password: uri.password)

require_relative "./cat_roamer"
require_relative './models/image.rb'

class CatApi < Roda
  include CatRoamer
  NO_CAT_LIST = ['austinkahly', 'murph', 'nichelle']

  plugin :json

  route do |r|

    def fake_response
      {"type"=>"interactive_message", "actions"=>[{"name"=>"aww", "type"=>"button", "value"=>"aww"}], "callback_id"=>"2ab45e8a0ff5d61a4ec257152b409b56e86ab005", "team"=>{"id"=>"T04T2GDGT", "domain"=>"wantable"}, "channel"=>{"id"=>"D2J26NNQG", "name"=>"directmessage"}, "user"=>{"id"=>"U050XHZV9", "name"=>"kevin"}, "action_ts"=>"1519872407.263251", "message_ts"=>"1519872405.000222", "attachment_id"=>"2", "token"=>"0f1X03bDgYgeWqGyqOZ3p6k6", "is_app_unfurl"=>false, "original_message"=>{"text"=>"", "bot_id"=>"B9C6LMCEN", "attachments"=>[{"fallback"=>"&lt;3 Cats &lt;3", "image_url"=>"https://cat--api.herokuapp.com/images/2ab45e8a0ff5d61a4ec257152b409b56e86ab005.jpg", "image_width"=>800, "image_height"=>533, "image_bytes"=>60383, "title"=>"Check out this cat", "id"=>1, "ts"=>1519872405, "color"=>"36a64f"}, {"callback_id"=>"2ab45e8a0ff5d61a4ec257152b409b56e86ab005", "fallback"=>"These cats are so cute.", "id"=>2, "actions"=>[{"id"=>"1", "name"=>"aww", "text"=>"aww", "type"=>"button", "value"=>"aww", "style"=>"primary"}, {"id"=>"2", "name"=>"dawww", "text"=>"dawww", "type"=>"button", "value"=>"dawww", "style"=>"danger"}]}], "type"=>"message", "subtype"=>"bot_message", "ts"=>"1519872405.000222"}, "response_url"=>"https://hooks.slack.com/actions/T04T2GDGT/322702357538/KDBIACHJwYaj6e5pWPPileAb", "trigger_id"=>"322822631461.4920557571.1c0fb85b51b7bf002fcc428571bd8820"}
    end

    r.root do
      "hello"
    end

    r.on "stats" do
      "#{Image.count} images in database."
    end

    r.on "cats.jpg" do
      response['Content-Type'] = "image/jpeg"
      fetch_random_cat.decoded_image
    end

    r.post "action" do
      payload = JSON.parse(r.params["payload"])

      if payload["callback_id"] and !Image.find_by_hashed_key(payload["callback_id"]).nil?
        message = modify_original_message(payload)
        message
      else
        {
          response_type: "ephemeral",
          replace_original: false,
          text: "Voting has closed."
        }
      end
    end

    r.on "cats" do
      if r.is_get?
        response['Content-Type'] = "image/jpeg"

        fetch_random_cat.decoded_image
      else
        response['Content-Type'] = 'application/json'
        if NO_CAT_LIST.include?(r.params["user_name"]) and r.params["text"] != "cats are great"
          image = Image.find_by_hashed_key(Image::MJ_HASHED_KEY)
          title = "Come back when you have a cat"
        else
          image = fetch_random_cat
          title = "Check out this cat"
          buttons = {
            fallback: "These cats are so cute.",
            callback_id: image.hashed_key,
            actions: [
              {
                name: "aww",
                text: AWW,
                type: "button",
                value: AWW,
                style: "primary"
              },
              {
                name: "dawww",
                text: DAWWW,
                type: "button",
                value: DAWWW,
                style: "danger"
              }
            ]
          }
        end
        message = {
          response_type: "in_channel",
          attachments: [
            {
              fallback: "<3 Cats <3",
              color: "#36a64f",
              title: title,
              title_link: "Cats",
              fields: [],
              image_url: image.url,
              thumb_url: image.url,
              ts: Time.now.to_i
            }
          ]
        }

        message[:attachments].push(buttons) unless buttons.nil?

        message.to_json
      end
    end

    r.on "images" do
      cleaned_key = request.remaining_path[1..-1].gsub(".jpg", "")
      response['Content-Type'] = "image/jpeg"

      if image = Image.find_by_hashed_key(cleaned_key)
        image.decoded_image
      elsif random_cat = fetch_random_cat
        random_cat.decoded_image
      end
    end

    # idk just give a random image
    r.get do
      if random_cat = fetch_random_cat
        response['Content-Type'] = "image/jpeg"
        random_cat.decoded_image
      end
    end

  end
end