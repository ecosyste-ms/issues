require "test_helper"

class OwnerTest < ActiveSupport::TestCase
  setup do
    @host = create_or_find_github_host
    @owner = Owner.create!(
      host: @host,
      login: "testuser",
      name: "Test User"
    )
  end

  test "should create owner" do
    assert @owner.valid?
    assert_equal "testuser", @owner.login
    assert_equal false, @owner.hidden
  end

  test "should hide owner" do
    assert_equal false, @owner.hidden
    @owner.hide!
    assert_equal true, @owner.hidden
  end

  test "should unhide owner" do
    @owner.hide!
    assert_equal true, @owner.hidden
    @owner.unhide!
    assert_equal false, @owner.hidden
  end

  test "visible scope should exclude hidden owners" do
    visible_owner = Owner.create!(host: @host, login: "visible_user", name: "Visible User")
    hidden_owner = Owner.create!(host: @host, login: "hidden_user", name: "Hidden User", hidden: true)

    visible_owners = Owner.visible
    assert visible_owners.include?(visible_owner)
    assert visible_owners.include?(@owner)
    assert_not visible_owners.include?(hidden_owner)
  end

  test "hidden scope should only include hidden owners" do
    hidden_owner = Owner.create!(host: @host, login: "hidden_user", name: "Hidden User", hidden: true)

    hidden_owners = Owner.hidden
    assert hidden_owners.include?(hidden_owner)
    assert_not hidden_owners.include?(@owner)
  end

  test "to_param should return login" do
    assert_equal "testuser", @owner.to_param
  end
end