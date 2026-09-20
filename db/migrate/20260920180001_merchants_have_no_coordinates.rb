class MerchantsHaveNoCoordinates < ActiveRecord::Migration[8.1]
  def up
    remove_column :merchants, :latitude
    remove_column :merchants, :longitude
  end

  def down
    add_column :merchants, :latitude, :decimal, precision: 10, scale: 6
    add_column :merchants, :longitude, :decimal, precision: 10, scale: 6
  end
end
