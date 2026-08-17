package agent

import "errors"

func validateSchedulerReservation(reservation SchedulerReservation) error {
	if reservation.ReservationID == "" || reservation.ReservationToken == "" {
		return errors.New("scheduler claim omitted reservation identity")
	}
	correlation := reservation.Correlation
	if correlation.RunnerInstanceID == "" || correlation.RunnerName == "" || correlation.PreparationID == "" || correlation.ReservationToken == "" {
		return errors.New("scheduler claim omitted runner correlation")
	}
	if correlation.ReservationToken != reservation.ReservationToken {
		return errors.New("scheduler claim returned mismatched reservation token")
	}
	return nil
}
