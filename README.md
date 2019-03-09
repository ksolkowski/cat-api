# cat-api



Hey dummy...


According to the Slack slash command documentation, you need to respond within 3000ms (three seconds). If your command takes longer then you get the Timeout was reached error. Your code obviously won't stop running, but the user won't get any response to their command.

Three seconds is fine for a quick thing where your command has instant access to data, but might not be long enough if you're calling out to external APIs or doing something complicated. If you do need to take longer, then see the Delayed responses and multiple responses section of the documentation:

Validate the request is okay.
Return a 200 response immediately, maybe something along the lines of {'text': 'ok, got that'}
Go and perform the actual action you want to do.
In the original request, you get passed a unique response_url parameter. Make a POST request to that URL with your follow-up message:
Content-type needs to be application/json
With the body as a JSON-encoded message: {'text': 'all done :)'}
you can return ephemeral or in-channel responses, and add attachments the same as the immediate approach
According to the docs, "you can respond to a user commands up to 5 times within 30 minutes of the user's invocation".