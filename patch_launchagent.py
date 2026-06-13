import re

with open("CI Scope/LocalBrokerLaunchAgent.swift", "r") as f:
    content = f.read()

content = content.replace("await currentValidUid()", "Optional(getuid())")
content = content.replace("uidStr = await ShellClient.run(\"id -u\", timeout: 3, config: config)\\n            .output\\n            .trimmingCharacters(in: .whitespacesAndNewlines)\\n        return Int(uidStr)", "return Int(getuid())")

with open("CI Scope/LocalBrokerLaunchAgent.swift", "w") as f:
    f.write(content)
