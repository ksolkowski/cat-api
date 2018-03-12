# ./app.rb
require "roda"
require "redis"
require "json"
require "open-uri"
require "sequel"
require "image_size"

ENV["SITE_URL"] ||= "localhost:3000"
ENV["RACK_ENV"] ||= "development"

if ENV['RACK_ENV'] == "production"
  DB = Sequel.connect(ENV["DATABASE_URL"])
else
  user     = 'root'
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

    r.root do
      "hello"
    end

    r.on "stats" do
      "#{Image.count} images in database."
    end

    r.on "cats.jpg" do
      response['Content-Type'] = "image/jpeg"
      fetch_random_cat(true).decoded_image
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

    r.on "square" do
      response['Content-Type'] = "image/jpeg"
      Image.random_square_image&.decoded_image
    end

    r.on "images" do
      cleaned_key = request.remaining_path[1..-1].gsub(".jpg", "")
      response['Content-Type'] = "image/jpeg"

      if image = Image.find_by_hashed_key(cleaned_key)
        image.decoded_image
      elsif random_cat = fetch_random_cat(true)
        random_cat.decoded_image
      end
    end

    # idk just give a random image
    r.get do
      if random_cat = fetch_random_cat(true)
        response['Content-Type'] = "image/jpeg"
        random_cat.decoded_image
      end
    end

  end
end