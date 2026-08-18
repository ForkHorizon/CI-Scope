package agent

import (
	"crypto/rand"
	"encoding/hex"
	"path/filepath"
)

func (s *HeadlessScheduler) runnerCommand(record *schedulerRecord) (socketCommand, error) {
	correlation := record.Reservation.Correlation
	if err := validateSchedulerReservation(record.Reservation); err != nil {
		return socketCommand{}, err
	}
	workspace := record.Reservation.Workspace
	if workspace == "" && s.config.RunnerWorkspace != "" {
		// The Actions runner creates its own job work directory below this
		// allowlisted root; do not invent a new filesystem side effect here.
		workspace = filepath.Clean(s.config.RunnerWorkspace)
	}
	executable := record.Reservation.Executable
	if executable == "" {
		executable = s.config.RunnerExecutable
	}
	correlationMap := map[string]any{
		"runnerInstanceId": correlation.RunnerInstanceID, "runnerName": correlation.RunnerName,
		"runnerGroupId": correlation.RunnerGroupID, "organizationId": correlation.OrganizationID,
		"installationId": correlation.InstallationID, "preparationId": correlation.PreparationID,
		"runnerAttempt": correlation.RunnerAttempt, "reservationToken": correlation.ReservationToken,
		"githubJobKey": nil, "runAttempt": nil,
	}
	if correlation.GitHubJobKey != "" {
		correlationMap["githubJobKey"] = correlation.GitHubJobKey
	}
	if correlation.RunAttempt != 0 {
		correlationMap["runAttempt"] = correlation.RunAttempt
	}
	return socketCommand{
		Command: "reservation.prepare", AppInstanceID: "", OperationID: record.PrepareRequestID,
		ReservationID: record.Reservation.ReservationID, RunnerInstanceID: correlation.RunnerInstanceID,
		Executable: executable, Workspace: workspace, RunnerCorrelation: correlationMap,
	}, nil
}

func newSchedulerRequestID(prefix string) (string, error) {
	bytes := make([]byte, 12)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return prefix + "." + hex.EncodeToString(bytes), nil
}
