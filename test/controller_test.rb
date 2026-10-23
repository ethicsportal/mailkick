require_relative "test_helper"

class ControllerTest < ActionDispatch::IntegrationTest
  def test_unsubscribe_url
    user = User.create!
    user.subscribe("sales")
    message = UserMailer.with(user: user).welcome.deliver_now
    text_body = message.text_part.body.to_s
    url = /Unsubscribe: (.+)/.match(text_body)[1]

    get url
    refute user.subscribed?("sales")
  end

  def test_unsubscribe_url_confirm_unsubscribe
    with_confirm_unsubscribe do
      user = User.create!
      user.subscribe("sales")
      message = UserMailer.with(user: user).welcome.deliver_now
      text_body = message.text_part.body.to_s
      url = /Unsubscribe: (.+)/.match(text_body)[1]

      get url
      assert user.subscribed?("sales")

      action = /action="([^"]+)"/.match(response.body)[1]
      post action
      refute user.subscribed?("sales")
    end
  end

  def test_unsubscribe_headers
    user = User.create!
    user.subscribe("sales")
    message = UserMailer.with(user: user).welcome.deliver_now
    url = message["List-Unsubscribe"].to_s[1..-2]

    post url, params: {"List-Unsubscribe" => "One-Click"}
    assert_response :success
    assert_includes "Unsubscribe successful", response.body
    refute user.subscribed?("sales")
  end

  def test_bad_signature
    user = User.create!
    message = UserMailer.with(user: user).welcome.deliver_now
    text_body = message.text_part.body.to_s
    url = /Unsubscribe: (.+)/.match(text_body)[1]

    get url.sub("/unsubscribe", "bad/unsubscribe")
    assert_response :bad_request
    assert_equal "Subscription not found", response.body
  end

  def test_resubscribe
    user = User.create!
    path = "/mailkick/subscriptions/#{Mailkick.generate_token(user, "sales")}"

    2.times do
      post "#{path}/subscribe"
      assert_redirected_to path
    end
    assert user.subscribed?("sales")
    assert_equal 1, Mailkick::Subscription.count
  end

  def test_resubscribe_get
    user = User.create!
    path = "/mailkick/subscriptions/#{Mailkick.generate_token(user, "sales")}"

    get "#{path}/subscribe"
    assert_redirected_to path
    assert user.subscribed?("sales")
  end

  def test_resubscribe_method
    user = User.create!
    path = "/mailkick/subscriptions/#{Mailkick.generate_token(user, "sales")}"
    received = nil
    callback = lambda do |**attributes|
      received = attributes
      "/subscriptions/pending"
    end

    with_resubscribe_method(callback) do
      post "#{path}/subscribe"
      assert_redirected_to "/subscriptions/pending"
      assert_equal({subscriber_type: "User", subscriber_id: user.id, list: "sales"}, received)
      refute user.subscribed?("sales")

      user.subscribe("sales")
      assert user.subscribed?("sales")
    end
  end

  def test_resubscribe_method_get
    user = User.create!
    path = "/mailkick/subscriptions/#{Mailkick.generate_token(user, "sales")}"

    with_resubscribe_method(->(**) { flunk "Callback must not run on GET" }) do
      get "#{path}/subscribe"
      assert_redirected_to path
      refute user.subscribed?("sales")
      follow_redirect!
      assert_response :success
      assert_includes response.body, "Resubscribe"
    end
  end

  def test_resubscribe_method_bad_signature
    user = User.create!
    token = Mailkick.generate_token(user, "sales")

    with_resubscribe_method(->(**) { flunk "Callback must not run for an invalid token" }) do
      post "/mailkick/subscriptions/#{token}tampered/subscribe"
      assert_response :bad_request
      refute user.subscribed?("sales")
    end
  end

  def test_resubscribe_method_error
    user = User.create!
    path = "/mailkick/subscriptions/#{Mailkick.generate_token(user, "sales")}"

    with_resubscribe_method(->(**) { raise "Confirmation unavailable" }) do
      post "#{path}/subscribe"
      assert_response :internal_server_error
      refute user.subscribed?("sales")
    end
  end

  def test_resubscribe_method_requires_csrf_token
    previous_value = Mailkick::SubscriptionsController.allow_forgery_protection
    Mailkick::SubscriptionsController.allow_forgery_protection = true
    user = User.create!
    path = "/mailkick/subscriptions/#{Mailkick.generate_token(user, "sales")}"

    with_resubscribe_method(->(**) { flunk "Callback must not run without a CSRF token" }) do
      post "#{path}/subscribe"
      assert_response :unprocessable_entity
      refute user.subscribed?("sales")
    end
  ensure
    Mailkick::SubscriptionsController.allow_forgery_protection = previous_value
  end

  def test_resubscribe_method_preserves_one_click_unsubscribe
    user = User.create!
    user.subscribe("sales")
    path = "/mailkick/subscriptions/#{Mailkick.generate_token(user, "sales")}"

    with_resubscribe_method(->(**) { flunk "Callback must not run for unsubscribe" }) do
      with_confirm_unsubscribe do
        post "#{path}/unsubscribe", params: {"List-Unsubscribe" => "One-Click"}
        assert_response :success
        refute user.subscribed?("sales")
      end
    end
  end
end
