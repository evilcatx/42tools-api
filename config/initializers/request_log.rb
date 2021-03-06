ActiveSupport::Notifications.subscribe('process_action.action_controller') do |name, started, finished, unique_id, payload|
  unless payload[:params][:controller].match(%r(^v\d+/auths$|oauth/callback))
    data = Bearer.decode(payload[:headers]['Authorization'])

    if data
      token = Token.find_by_id(data['app_token_id'])

      token.logs.create!(data: {
        remote_ip: payload[:headers]['action_dispatch.remote_ip'].to_s,
        controller: payload[:params][:controller],
        action: payload[:params][:action],
        params: payload[:params].reject { |k, v| k.in?(%w(controller action)) }.as_json,
        verb: payload[:method],
        status: payload[:status],
        view_runtime: payload[:view_runtime],
        db_runtime: payload[:db_runtime],
        started_at: started,
        finished_at: finished
      }) if token
    end
  end
end
