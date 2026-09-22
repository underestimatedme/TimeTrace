package timetrace

import (
	"encoding/json"
	"net/http/httptest"
	"os"
	"os/exec"
	"strings"
	"testing"
	"time"
)

func TestF09PythonRunnerCancellationBatch(t *testing.T) {
	if dsn := os.Getenv("APP_DSN_TIMETRACE_TEST"); !strings.Contains(dsn, "host=127.0.0.1") || !strings.Contains(dsn, "port=54329") {
		t.Fatal("requires isolated loopback PostgreSQL on 54329")
	}
	script := os.Getenv("F09_RUNNER_SCENARIO")
	if script == "" {
		t.Fatal("F09_RUNNER_SCENARIO must name the TimeTrace integration script")
	}
	python := os.Getenv("F09_PYTHON")
	if python == "" {
		python = "python3"
	}
	for _, lostReply := range []bool{false, true} {
		name := "cancel"
		if lostReply {
			name = "cancel_lost_reply"
		}
		t.Run(name, func(t *testing.T) {
			h, s, _, task := workspaceFixture(t)
			first := workspaceJob(t, h, s, task, "", "first")
			task2 := seedTask(t, h, User{ID: task.UserID}, "second-task")
			second := workspaceJob(t, h, s, task2, "", "second")
			if err := h.db.Model(&RemoteJob{}).Where("id = ?", first.ID).Update("created_at", time.Now().Add(-time.Second)).Error; err != nil {
				t.Fatal(err)
			}
			server := httptest.NewServer(h.router)
			defer server.Close()
			raw, _ := json.Marshal(map[string]any{"url": server.URL + apiPrefix, "owner": s.AccessToken, "runner": "workspace-token", "first": first.ID, "second": second.ID, "lost_reply": lostReply})
			cmd := exec.Command(python, script)
			cmd.Stdin = strings.NewReader(string(raw))
			out, err := cmd.CombinedOutput()
			if err != nil {
				t.Fatalf("real Python Runner: %v\n%s", err, out)
			}
			var result struct {
				Events []RemoteEventInput `json:"events"`
			}
			if err := json.Unmarshal(out, &result); err != nil {
				t.Fatalf("scenario output: %s (%v)", out, err)
			}
			var job RemoteJob
			if err := h.db.Where("id = ?", first.ID).Take(&job).Error; err != nil {
				t.Fatal(err)
			}
			if job.Status != "cancelled" || job.DesiredAction != "cancel" {
				t.Fatalf("terminal state: %+v", job)
			}
			var events []RemoteEvent
			if err := h.db.Where("job_id = ?", first.ID).Order("sequence").Find(&events).Error; err != nil {
				t.Fatal(err)
			}
			if len(events) != 2 || len(result.Events) != 2 {
				t.Fatalf("atomic events not retained: %+v", events)
			}
			for i, event := range events {
				sent := result.Events[i]
				if event.Sequence != sent.Sequence || event.Type != sent.Type || event.ObservedAt == nil || sent.ObservedAt == nil || !event.ObservedAt.Equal(*sent.ObservedAt) {
					t.Fatalf("event rewritten: %+v vs %+v", event, sent)
				}
				if event.CreatedAt.Before(event.ObservedAt.Add(-2 * time.Second)) {
					t.Fatal("invalid observation")
				}
			}
			var attempt RemoteAttempt
			if err := h.db.Where("id = ?", events[0].AttemptID).Take(&attempt).Error; err != nil {
				t.Fatal(err)
			}
			if attempt.EndedAt == nil || attempt.LastSequence != 2 {
				t.Fatalf("attempt ended before whole batch: %+v", attempt)
			}
			job = RemoteJob{}
			if err := h.db.Where("id = ?", second.ID).Take(&job).Error; err != nil {
				t.Fatal(err)
			}
			if job.Status != "awaiting_review" {
				t.Fatalf("next claim blocked: %+v", job)
			}
			t.Log("real HTTP/Python/PostgreSQL: cancelled, original events retained, outbox drained, next job executed")
		})
	}
}
