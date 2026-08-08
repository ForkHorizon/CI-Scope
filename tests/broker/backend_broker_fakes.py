"""Stand-ins for the subprocess and SSE stream the broker talks to."""

class MockProcess:
    pid = 9999


class FakeSSEResponse:
    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def __iter__(self):
        return iter(
            [
                b"id: 12\n",
                b"event: workflow_job\n",
                b"data: {}\n",
                b"\n",
            ]
        )
