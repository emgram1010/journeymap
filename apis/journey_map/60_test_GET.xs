query test verb=GET {
  api_group = "journey-map"

  input {
    text message? filters=trim
  }

  stack {
    var $messages {
      value = [{role: "user", content: $input.message}]
    }
  
    ai.agent.run "Journey Map Assistant" {
      args = {}|set:"messages":$messages
      allow_tool_execution = true
      version = "v5"
    } as $Journey_Map_Assistant1
  }

  response = $Journey_Map_Assistant1
}