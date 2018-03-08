require 'base64'
require 'open-uri'
require 'nokogiri'
module CatRoamer
  STORED_HASH_KEY  = "cats:images"  # redis set [encoded_keys]
  VOTING_CAT_KEY   = "cats:voting"  #
  AWW   = "aww"
  DAWWW = "dawww"

  def fetch_random_cat(true_random=false)
    hashed_key = $redis.srandmember(STORED_HASH_KEY)
    if hashed_key and !true_random
      Image.find_by_hashed_key(hashed_key)
    else
      Image.random
    end
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
    original_attachment["actions"].sort_by{|btn| btn["value"] == action_button["value"] ? 0 : 1 }.each do |btn|
      vote_key = btn["value"] == AWW ? AWW : DAWWW
      store_or_remove_user_vote(callback_id, user, vote_key) if btn["value"] == action_button["value"] # this is the action

      votes = vote_count(callback_id, vote_key)
      if votes > 0
        btn["text"] = "#{vote_key} (#{votes})"
      else
        btn["text"] = vote_key
      end

      btn
    end

    original_message["replace_original"] = true
    original_message
  end

  def vote_count(callback_id, vote_key)
    set_key = "#{VOTING_CAT_KEY}:#{vote_key}:#{callback_id}"
    $redis.scard(set_key) # return the count
  end

  def store_or_remove_user_vote(callback_id, user, vote_key)
    user_id = user["id"]
    set_key = "#{VOTING_CAT_KEY}:#{vote_key}:#{callback_id}"
    other_key = "#{VOTING_CAT_KEY}:#{(vote_key == AWW ? DAWWW : AWW)}:#{callback_id}"
    # if they are a member of other key remove the vote and add a vote
    if $redis.sismember(other_key, user_id)
      $redis.srem(other_key, user_id)
      $redis.sadd(set_key, user_id)
    elsif $redis.sismember(set_key, user_id) # remove vote
      $redis.srem(set_key, user_id)
    else
      $redis.sadd(set_key, user_id)
    end
  end

  def clear_and_store_cat_keys(keys)
    Image.where(hashed_key: $redis.smembers(STORED_HASH_KEY)).each do |image|
      $redis.del("#{VOTING_CAT_KEY}:#{AWW}:#{image.hashed_key}")
      $redis.del("#{VOTING_CAT_KEY}:#{DAWWW}:#{image.hashed_key}")
    end
    $redis.del STORED_HASH_KEY
    $redis.sadd STORED_HASH_KEY, keys
  end

end