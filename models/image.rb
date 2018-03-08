class Image < Sequel::Model
  MJ_HASHED_KEY = "082fc1f97d88b237855e05a01dba0f209ecca55c"
  plugin :validation_helpers

  def before_create
    data = open(self.original_url)

    self.hashed_key = Digest::SHA1.hexdigest(self.original_url)
    self.width  = sizes.width
    self.height = sizes.height
    self.encoded_image = Base64.encode64(data.read)
    super
  end

  def validate
    super
    validates_presence :original_url
  end

  def self.find_by_hashed_key(hashed_key)
    Image.where(hashed_key: hashed_key).first
  end

  def self.random(limit=1, base=Image)
    images = base.exclude(hashed_key: MJ_HASHED_KEY).order(Sequel.lit('RANDOM()')).limit(limit)
    if limit == 1
      images.first
    else
      images
    end
  end

  def self.random_square_image
    image = Image.where{Sequel.lit('images.height = images.width')}.exclude(hashed_key: MJ_HASHED_KEY).order(Sequel.lit('RANDOM()')).limit(1).first
    # welp no perfect squares
    if image.nil?
      size_diff = 25
      while image.nil?
        image = Image.exclude(hashed_key: MJ_HASHED_KEY).
                where{Sequel.lit('abs(images.height - images.width) <= ?', size_diff)}.
                order(Sequel.lit('RANDOM()')).limit(1).first
        size_diff += 25
      end
    end

    image
  end

  def self.save_and_store_urls(urls)
    urls.map do |url|
      image = Image.new(original_url: url)
      image.save
      sleep 5
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