require 'base64'
require 'open-uri'
require 'nokogiri'
module CatRoamer
  URL_KEY          = "cats:urls"    # redis list of urls
  STORED_IMAGE_KEY = "cats:images"  # redis hash {sha8_key => stored_image}
  VIEWED_CAT_KEY   = "cats:views"   # redis hash {sha8_key => view_count}
  VOTING_CAT_KEY   = "cats:voting"
  AWW   = "aww"
  DAWWW = "dawww"

  def fetch_or_download_cat_urls
    url = $redis.srandmember(URL_KEY) # cats exist

    if url.nil?
      page = (0..2010).to_a.sample
      html = Nokogiri::HTML(open("http://d.hatena.ne.jp/fubirai/?of=#{page}"))
      cat_urls = html.css("img.hatena-fotolife").to_a.map{|child| child.attributes["src"].value }
      url = cat_urls.sample
    end

    save_or_fetch_image_in_redis(url)
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
  def modify_original_message(payload)
    original_message = payload["original_message"]
    callback_id = payload["callback_id"]
    action_button = payload['actions'].first # what button was pressed
    original_attachment = original_message['attachments'].find{|x| x["callback_id"] == callback_id }
    user = payload["user"]
    original_attachment["actions"].sort_by{|btn| btn["value"] == action_button["value"] }.each do |btn|
      vote_key = btn["value"] == AWW ? AWW : DAWWW

      if btn["value"] == action_button["value"] # this is the action
        store_or_remove_user_vote(callback_id, user, vote_key)
      end

      votes = vote_count(callback_id, vote_key)

      puts "#{vote_key}: #{votes}"

      btn["text"] = "#{vote_key} (#{votes})"

      btn
    end

    #original_attachment["actions"] = actions

    original_message["replace_original"] = true
    original_message
  end

  def vote_count(callback_id, vote_key)
    puts "count: callback_id:#{callback_id}, vote_key:#{vote_key}"
    set_key = "#{VOTING_CAT_KEY}:#{vote_key}:#{callback_id}"
    $redis.scard(set_key) # return the count
  end

  def store_or_remove_user_vote(callback_id, user, vote_key)
    puts "key: #{callback_id}, user: #{user}, vote_key: #{vote_key}"
    user_id = user["id"]
    set_key = "#{VOTING_CAT_KEY}:#{vote_key}:#{callback_id}"
    other_key = "#{VOTING_CAT_KEY}:#{(vote_key == AWW ? DAWWW : AWW)}:#{callback_id}"
    # if they are a member of other key remove the vote and add a vote
    if $redis.sismember(other_key, user_id)
      puts "is other member"
      $redis.srem(other_key, user_id)
      $redis.sadd(set_key, user_id)
    elsif $redis.sismember(set_key, user_id) # remove vote
      puts "is member removing vote"
      $redis.srem(set_key, user_id)
    else
      puts "adding vote"
      $redis.sadd(set_key, user_id)
    end
  end

  def get_cat_stats
    @images_saved = fetch_all_stored_images.count
    @urls_saved = $redis.scard(URL_KEY)
    @views = fetch_all_views
  end

  def fetch_all_views
    $redis.hgetall VIEWED_CAT_KEY
  end

  def increment_view_count(base_key)
    $redis.hincrby VIEWED_CAT_KEY, base_key, 1
  end

  def store_cat_urls(urls)
    $redis.sadd URL_KEY, urls
  end

  def store_cat_url(url)
    $redis.sadd URL_KEY, url
  end

  def remove_cat_url(url)
    $redis.srem URL_KEY, url
  end

  def remove_url_and_image(url)
    remove_cat_url(url)
    key = base_redis_key(url)
    $redis.hdel STORED_IMAGE_KEY, key
    $redis.hdel VIEWED_CAT_KEY, key

  end

  def fetch_all_stored_images
    $redis.hkeys(STORED_IMAGE_KEY)
  end

  def clear_cached_cats
    $redis.del URL_KEY
    count = $redis.hkeys(STORED_IMAGE_KEY).count
    $redis.del STORED_IMAGE_KEY
    $redis.del VIEWED_CAT_KEY

    count
  end

  def already_saved?(key)
    $redis.hexists(STORED_IMAGE_KEY, key)
  end

  def fetch_saved_image(key)
    $redis.hget(STORED_IMAGE_KEY, key)
  end

  def save_image(url, key)
    raw_img = Base64.encode64(open(url).read)
    store_cat_url(url)
    $redis.hset STORED_IMAGE_KEY, key, raw_img
    raw_img
  end

  def fetch_and_decode(key)
    raw_img = fetch_saved_image(key)
    decode_image(raw_img)
  end

  def key_to_path(key)
    key + ".jpg"
  end

  def save_image_in_redis(url)
    key = base_redis_key(url)
    save_image(url, key)
  end

  def save_or_fetch_image_in_redis(url)
    key = base_redis_key(url)

    if already_saved?(key)
      raw_img = fetch_saved_image(key)
    else # store it in redis
      raw_img = save_image(url, key)
    end

    [decode_image(raw_img), key_to_path(key)]
  end

  def clean_key(key)
    key.gsub(".jpg", "")
  end

  private

  def base_redis_key(url)
    Digest::SHA1.hexdigest(url)
  end

  def decode_image(raw_img)
    Base64.decode64 raw_img
  end

  def base_key(key)
    key.split(":").last
  end

end