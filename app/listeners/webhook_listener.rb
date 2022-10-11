class WebhookListener < BaseListener
  def conversation_status_changed(event)
    conversation = extract_conversation_and_account(event)[0]
    changed_attributes = extract_changed_attributes(event)
    inbox = conversation.inbox
    payload = conversation.webhook_data.merge(event: __method__.to_s, changed_attributes: changed_attributes)
    deliver_webhook_payloads(payload, inbox)
  end

  def conversation_updated(event)
    conversation = extract_conversation_and_account(event)[0]
    changed_attributes = extract_changed_attributes(event)
    inbox = conversation.inbox
    payload = conversation.webhook_data.merge(event: __method__.to_s, changed_attributes: changed_attributes)
    deliver_webhook_payloads(payload, inbox)
  end

  def conversation_created(event)
    conversation = extract_conversation_and_account(event)[0]
    inbox = conversation.inbox
    payload = conversation.webhook_data.merge(event: __method__.to_s)
    deliver_webhook_payloads(payload, inbox)
  end

  def message_created(event)
    message = extract_message_and_account(event)[0]
    inbox = message.inbox

    return unless message.webhook_sendable?

    payload = message.webhook_data.merge(event: __method__.to_s)
    deliver_webhook_payloads(payload, inbox)
  end

  def message_updated(event)
    message = extract_message_and_account(event)[0]
    inbox = message.inbox

    return unless message.webhook_sendable?

    payload = message.webhook_data.merge(event: __method__.to_s)
    deliver_webhook_payloads(payload, inbox)
  end

  def webwidget_triggered(event)
    contact_inbox = event.data[:contact_inbox]
    inbox = contact_inbox.inbox

    payload = contact_inbox.webhook_data.merge(event: __method__.to_s)
    payload[:event_info] = event.data[:event_info]
    deliver_webhook_payloads(payload, inbox)
  end

  private

  def deliver_account_webhooks(payload, inbox)
    inbox.account.webhooks.account.each do |webhook|
      next unless webhook.subscriptions.include?(payload[:event])

      WebhookJob.perform_later(webhook.url, payload)
    end
  end

  def deliver_api_inbox_webhooks(payload, inbox)
    return unless inbox.channel_type == 'Channel::Api'
    return if inbox.channel.webhook_url.blank?

    WebhookJob.perform_later(inbox.channel.webhook_url, payload)
  end

  def deliver_whatsapp_inbox_webhooks(payload, inbox)
    payload = payload.deep_symbolize_keys
    return unless inbox.channel_type == 'Channel::Whatsapp' && payload[:event] == 'message_updated'

    message_type = ['incoming', 0, '0']
    messages = (payload.dig(:conversation, :messages) || []).select do |m|
      m[:status] == 'read' && message_type.include?(m[:message_type])
    end
    messages.each do |message|
      WebhookJob.perform_later(
        inbox.channel.message_path(message),
        inbox.channel.message_update_payload(message),
        inbox.channel.message_update_http_method,
        inbox.channel.api_headers
      )
    end
  end

  def deliver_webhook_payloads(payload, inbox)
    deliver_account_webhooks(payload, inbox)
    deliver_api_inbox_webhooks(payload, inbox)
    deliver_whatsapp_inbox_webhooks(payload, inbox)
  end
end
