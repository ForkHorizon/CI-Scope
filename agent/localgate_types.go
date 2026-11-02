// Wire types for local gate jobs and reports.
package agent

// LocalGateJob is one pull request the server wants checked on this device.
type LocalGateJob struct {
	ID          string `json:"id"`
	Repository  string `json:"repository"`
	PullRequest int    `json:"pullRequest"`
	HeadSHA     string `json:"headSha"`
	BaseSHA     string `json:"baseSha"`
	HeadBranch  string `json:"headBranch"`
	BaseBranch  string `json:"baseBranch"`
}

// LocalGateCheck is the outcome of a single check inside a report.
type LocalGateCheck struct {
	ID       string `json:"id"`
	Status   string `json:"status"`
	Required bool   `json:"required"`
	Detail   string `json:"detail"`
}

// LocalGateReport is what the server turns into the GitHub check run.
type LocalGateReport struct {
	Status      string           `json:"status"`
	Summary     string           `json:"summary"`
	Checks      []LocalGateCheck `json:"checks"`
	CompletedAt int64            `json:"completedAt"`
	// ConfigVersion is the server config version the run used; zero when unknown.
	ConfigVersion int `json:"configVersion,omitempty"`
}
