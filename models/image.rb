class Image < Sequel::Model
  MJ_HASHED_KEY = "082fc1f97d88b237855e05a01dba0f209ecca55c"
  plugin :validation_helpers

  def before_create
    self.hashed_key = Digest::SHA1.hexdigest(self.original_url)
    self.encoded_image = Base64.encode64(open(self.original_url).read)
    super
  end

  def validate
    super
    validates_presence :original_url
  end

  def self.find_by_hashed_key(hashed_key)
    Image.where(hashed_key: hashed_key).first
  end

  def self.save_and_store_urls(urls)
    urls.map do |url|
      image = Image.new(original_url: url)
      image.save

      image
    end
  end

  def decoded_image
    Base64.decode64 encoded_image
  end

  def url
    File.join ENV["SITE_URL"], 'images', hashed_key
  end

end