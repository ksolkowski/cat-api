class Image < Sequel::Model
  MJ_HASHED_KEY = "082fc1f97d88b237855e05a01dba0f209ecca55c"

  plugin :validation_helpers

  include ColorCache

  def before_create
    data = open(self.original_url)
    self.encoded_image = Base64.encode64(data.read)
    self.hashed_key    = Digest::SHA1.hexdigest(self.original_url)
    self.width  = sizes.width
    self.height = sizes.height
    super
  end

  def validate
    super
    validates_presence :original_url
  end

  def self.find_by_hashed_key(hashed_key)
    Image.where(hashed_key: hashed_key).first
  end

  def self.random(limit=1)
    images = Image.exclude(hashed_key: MJ_HASHED_KEY).order(Sequel.lit('RANDOM()')).limit(limit)
    if limit == 1
      images.first
    else
      images
    end
  end

  def self.save_and_store_urls(urls, nap_length=5)
    urls.map do |url|
      image = Image.new(original_url: url)
      image.save
      sleep nap_length
      image
    end
  end

  def decoded_image
    Base64.decode64 encoded_image
  end

  def url
    File.join ENV["SITE_URL"], 'images', hashed_key
  end

  def sizes
    @sizes ||= ImageSize.new(decoded_image)
  end

end