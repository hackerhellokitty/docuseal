# frozen_string_literal: true

class SendSubmissionCreatedWebhookRequestJob
  include Sidekiq::Job

  sidekiq_options queue: :webhooks

  MAX_ATTEMPTS = 10

  def perform(params = {})
    submission = Submission.find(params['submission_id'])
    webhook_url = WebhookUrl.find(params['webhook_url_id'])

    attempt = params['attempt'].to_i

    return if webhook_url.url.blank? || webhook_url.events.exclude?('submission.created')

    resp = SendWebhookRequest.call(webhook_url, event_type: 'submission.created',
                                                event_uuid: params['event_uuid'],
                                                record: submission,
                                                attempt:,
                                                data: Submissions::SerializeForApi.call(submission))

    if (resp.nil? || resp.status.to_i >= 400) && attempt <= MAX_ATTEMPTS &&
       (!Docuseal.multitenant? || submission.account.account_configs.exists?(key: :plan))
      SendSubmissionCreatedWebhookRequestJob.perform_in((2**attempt).minutes, {
                                                          **params,
                                                          'attempt' => attempt + 1,
                                                          'last_status' => resp&.status.to_i
                                                        })
    end
  end
end
