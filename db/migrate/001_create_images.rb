Sequel.migration do
  change do
    ### Add Migration
    create_table(:images) do
      primary_key :id, unique: true
      String :hashed_key, null: false
      String :original_url, unique: true, null: false
      TEXT   :encoded_image, null: false
    end
  end
end