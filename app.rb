# ./app.rb
require "roda"
require 'redis'
require 'json'
require 'open-uri'

require_relative "./cat_roamer"

uri = URI.parse(ENV["REDIS_URL"]||"redis://localhost:6379")
$redis = Redis.new(host: uri.host, port: uri.port, password: uri.password)
ENV["SITE_URL"] ||= "localhost:3000"
ENV["RACK_ENV"] ||= "development"

class CatApi < Roda
  include CatRoamer
  NO_CAT_LIST = ['austinkahly', 'murph', 'nichelle']

  plugin :json

  route do |r|

    r.root do
      "hello"
    end

    r.on "stats" do
      get_cat_stats
      "#{@images_saved} images in redis. #{@urls_saved} urls in redis. #{@views}"
    end

    r.on "cats.jpg" do
      response['Content-Type'] = "image/jpeg"
      decoded_image, fake_path = fetch_or_download_cat_urls
      decoded_image
    end

    # response
    # {
    #   "type"=>"interactive_message",
    #   "actions"=>[{"name"=>"recommend", "type"=>"button", "value"=>"recommend"}],
    #   "callback_id"=>"fc019dbcdca7bbba4439c990d0127e708254743d.jpg",
    #   "team"=>{"id"=>"T04T2GDGT", "domain"=>"wantable"}, "channel"=>{"id"=>"D2J26NNQG", "name"=>"directmessage"},
    #   "user"=>{"id"=>"U050XHZV9", "name"=>"kevin"},
    #   "action_ts"=>"1519690770.689609",
    #   "message_ts"=>"1519690768.000289",
    #   "attachment_id"=>"2",
    #   "token"=>"0f1X03bDgYgeWqGyqOZ3p6k6",
    #   "is_app_unfurl"=>false,
    #   "original_message"=>{
    #     "text"=>"", "bot_id"=>"B9C6LMCEN",
    #     "attachments"=>[
    #       {
    #         "fallback"=>"&lt;3 Cats &lt;3", "image_url"=>"https://cat--api.herokuapp.com/images/fc019dbcdca7bbba4439c990d0127e708254743d.jpg",
    #         "image_width"=>533, "image_height"=>800, "image_bytes"=>80580, "title"=>"Check out this cat", "id"=>1, "ts"=>1519690768, "color"=>"36a64f"
    #       },
    #       {
    #         "callback_id"=>"fc019dbcdca7bbba4439c990d0127e708254743d.jpg", "fallback"=>"These cats are so cute.",
    #         "id"=>2,
    #         "actions"=>[
    #           {"id"=>"1", "name"=>"recommend", "text"=>"Recommend", "type"=>"button", "value"=>"recommend", "style"=>"primary"},
    #           {"id"=>"2", "name"=>"no", "text"=>"No", "type"=>"button", "value"=>"bad", "style"=>"danger"}
    #         ]
    #       }
    #     ],
    #     "type"=>"message", "subtype"=>"bot_message", "ts"=>"1519690768.000289"
    #   },
    #   "response_url"=>"https://hooks.slack.com/actions/T04T2GDGT/322306029399/HcNjaRaw6yIwS6xmUSlm6XqL",
    #   "trigger_id"=>"322102643078.4920557571.0c5718dab274953c5044f88938378511"
    # }
    r.post "action" do
      payload = JSON.parse(r.params["payload"])
      puts payload
      original_message = payload["original_message"]
      action_button = payload['actions'].first
      original_attachment = original_message['attachments'].find{|x| x["callback_id"] == payload["callback_id"] }
      if btn = original_attachment["actions"].find{|x| x['value'] == action_button["value"] }
        btn.text = "aples"
      end


      original_message["replace_original"] = true
      original_message
    end

    r.on "cats" do
      if r.is_get?
        response['Content-Type'] = "image/jpeg"
        decoded_image, fake_path = fetch_or_download_cat_urls
        decoded_image
      else
        response['Content-Type'] = 'application/json'
        if NO_CAT_LIST.include?(r.params["user_name"]) and r.params["text"] != "cats are great"
          # mj cat http://nbacatwatch.com/wp-content/uploads/2017/10/f98a5f820283e9fada580d5f6d2f3e81.jpg
          {
            response_type: "in_channel",
            text: "Come back when you have a cat"
          }
        else
          decoded_image, fake_path = fetch_or_download_cat_urls

          real_url = File.join ENV["SITE_URL"], 'images', fake_path
          message = {
            response_type: "in_channel",
            attachments: [
              {
                fallback: "<3 Cats <3",
                color: "#36a64f",
                title: "Check out this cat",
                title_link: "Cats",
                fields: [],
                image_url: real_url,
                ts: Time.now.to_i
              }
            ]
          }

          if r.params["text"] == "buttons"
            test = {
              fallback: "These cats are so cute.",
              callback_id: fake_path,
              actions: [
                {
                  name: "recommend",
                  text: "Recommend",
                  type: "button",
                  value: "recommend",
                  style: "primary"
                },
                {
                  name: "no",
                  text: "No",
                  type: "button",
                  value: "bad",
                  style: "danger"
                }
              ]
            }
            message[:attachments].push test
          end

          message.to_json
        end
      end
    end

    r.on "clear_cats" do
      count = clear_cached_cats
      "cleared #{count} images"
    end

    r.on "images" do
      cleaned_key = request.remaining_path[1..-1].gsub(".jpg", "")
      response['Content-Type'] = "image/jpeg"
      if already_saved?(cleaned_key)
        fetch_and_decode(cleaned_key)
      end
    end

    # idk just give a random image
    r.get do
      if random_key = fetch_all_stored_images.sample # idk pick some random cat
        response['Content-Type'] = "image/jpeg"
        increment_view_count(random_key)
        fetch_and_decode(random_key)
      end

    end

  end
end