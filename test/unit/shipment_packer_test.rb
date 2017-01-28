require 'test_helper'

class ShipmentPackerTest < ActiveSupport::TestCase
  def setup
    @dimensions = [5.1, 15.2, 30.5]
  end

  def test_pack_divide_order_into_a_single_package
    items = [{:grams => 1, :quantity => 1, :price => 1.0}]

    packages = ShipmentPacker.pack(items, @dimensions, 1, 'USD')
    assert_equal 1, packages.size

    package = packages.first
    assert_equal Measured::Weight(1, :g), package.weight
  end

  def test_divide_order_with_multiple_lines_into_a_single_package
    items = [{:grams => 1, :quantity => 2, :price => 1.0}]

    packages = ShipmentPacker.pack(items, @dimensions, 2, 'USD')
    assert_equal 1, packages.size

    package = packages.first
    assert_equal Measured::Weight(2, :g), package.weight
  end

  def test_divide_order_with_single_line_into_two_packages
    items = [{:grams => 1, :quantity => 2, :price => 1.0}]

    packages = ShipmentPacker.pack(items, @dimensions, 1, 'USD')
    assert_equal 2, packages.size

    packages.each do |package|
      assert_equal Measured::Weight(1, :g), package.weight
    end
  end

  def test_divide_order_with_multiple_lines_into_two_packages
    items = [
      {:grams => 1, :quantity => 1, :price => 1.0},
      {:grams => 1, :quantity => 1, :price => 1.0}
    ]

    packages = ShipmentPacker.pack(items, @dimensions, 1, 'USD')
    assert_equal 2, packages.size

    packages.each do |package|
      assert_equal Measured::Weight(1, :g), package.weight
    end
  end

  def test_divide_order_into_two_packages_mixing_line_items
    items = [
      {:grams => 1, :quantity => 1, :price => 1.0},
      {:grams => 1, :quantity => 1, :price => 1.0},
      {:grams => 1, :quantity => 1, :price => 1.0}
    ]

    packages = ShipmentPacker.pack(items, @dimensions, 2, 'USD')
    assert_equal 2, packages.size

    assert_equal Measured::Weight(2, :g), packages[0].weight
    assert_equal Measured::Weight(1, :g), packages[1].weight
  end

  def test_raise_overweight_exception_when_a_single_item_exceeds_the_maximum_weight_of_a_package
    assert_raises(ShipmentPacker::OverweightItem) do
      items = [{:grams => 2, :quantity => 1, :price => 1.0}]
      ShipmentPacker.pack(items, @dimensions, 1, 'USD')
    end
  end

  def test_raise_over_weight_exceptions_before_over_package_limit_exceptions
      assert_raises(ShipmentPacker::OverweightItem) do
        items = [{:grams => 5, :quantity => ShipmentPacker::EXCESS_PACKAGE_QUANTITY_THRESHOLD + 1, :price => 1.0}]
        ShipmentPacker.pack(items, @dimensions, 4, 'USD')
      end
  end

  def test_returns_an_empty_list_when_no_items_provided
    assert_equal [], ShipmentPacker.pack([], @dimensions, 1, 'USD')
  end

  def test_add_summarized_prices_for_all_items_and_currency_to_package
    items = [
      {:grams => 1, :quantity => 3, :price => 1.0},
      {:grams => 2, :quantity => 1, :price => 2.0}
    ]
    packages = ShipmentPacker.pack(items, @dimensions, 5, 'USD')
    assert_equal 1, packages.size
    assert_equal 500, packages.first.value
    assert_equal 'USD', packages.first.currency
  end

  def test_divide_items_and_prices_accordingly_when_splitting_into_two_packages
    items = [
      {:grams => 1, :quantity => 1, :price => 1.0},
      {:grams => 1, :quantity => 1, :price => 1.0},
      {:grams => 1, :quantity => 1, :price => 1.0}
    ]

    packages = ShipmentPacker.pack(items, @dimensions, 2, 'USD')
    assert_equal 2, packages.size

    assert_equal 200, packages[0].value
    assert_equal 100, packages[1].value
    assert_equal 'USD', packages[0].currency
    assert_equal 'USD', packages[1].currency
  end

  def test_symbolize_item_keys
    string_key_items          = [{'grams' => 1, 'quantity' => 1, 'price' => 1.0}]
    indifferent_access_items  = [{'grams' => 1, 'quantity' => 1, 'price' => 1.0}.with_indifferent_access]

    [string_key_items, indifferent_access_items].each do |items|
      packages = ShipmentPacker.pack(items, @dimensions, 1, 'USD')
      assert_equal 1, packages.size

      package = packages.first
      assert_equal Measured::Weight(1, :g), package.weight
      assert_equal 100, package.value
    end
  end

  def test_cast_quantity_and_grams_to_int
    items = [{:grams => '1', :quantity => '1', :price => '1.0'}]

    packages = ShipmentPacker.pack(items, @dimensions, 1, 'USD')

    package = packages.first
    assert_equal Measured::Weight(1, :g), package.weight
    assert_equal 100, package.value
  end

  def test_excess_packages
    assert_raises(ShipmentPacker::ExcessPackageQuantity) do
      items = [{:grams => 1, :quantity => ShipmentPacker::EXCESS_PACKAGE_QUANTITY_THRESHOLD + 1, :price => 1.0}]
      ShipmentPacker.pack(items, @dimensions, 1, 'USD')
    end
  end

  def test_lots_of_zero_weight_items
    items = [{:grams => 0, :quantity => 1_000_000, :price => 1.0}]
    packages = ShipmentPacker.pack(items, @dimensions, 1, 'USD')

    assert_equal 1, packages.size
    assert_equal 0, packages[0].grams
    assert_equal 100_000_000, packages[0].value
  end

  def test_dont_destroy_input_items
    items = [{:grams => 1, :quantity => 5, :price => 1.0}]

    packages = ShipmentPacker.pack(items, @dimensions, 10, 'USD')

    assert_equal 1, items.size
    assert_equal 1, packages.size
  end

  def test_dont_modify_input_item_quantities
    items = [{:grams => 1, :quantity => 5, :price => 1.0}]

    ShipmentPacker.pack(items, @dimensions, 10, 'USD')
    assert_equal 5, items.first[:quantity]
  end

  def test_items_with_negative_weight
    items = [{:grams => -1, :quantity => 5, :price => 1.0}]

    ShipmentPacker.pack(items, @dimensions, 10, 'USD')
    assert_equal 5, items.first[:quantity]
  end
end
