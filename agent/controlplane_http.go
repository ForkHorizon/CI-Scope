package agent

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"strings"
)

const maxServerResponseBytes int64 = 1 << 20

type HTTPControlPlane struct {
	baseURL         *url.URL
	client          *http.Client
	credentialProof string
}

// HTTPControlPlaneRequestHeaders contains per-request credentials. The
// control-plane client never forwards the process environment implicitly.
type HTTPControlPlaneRequestHeaders struct {
	Authorization    string
	EnrollmentIssuer string
}

func NewHTTPControlPlane(rawURL string, client *http.Client, credentialProof string) (*HTTPControlPlane, error) {
	parsed, err := url.Parse(rawURL)
	if err != nil || parsed.Scheme != "https" || parsed.Host == "" {
		return nil, errors.New("control-plane URL must be an absolute HTTPS URL")
	}
	if client == nil {
		client = http.DefaultClient
	}
	return &HTTPControlPlane{baseURL: parsed, client: client, credentialProof: credentialProof}, nil
}

func (c *HTTPControlPlane) Do(ctx context.Context, path string, request ServerRequestEnvelope) (ServerResponseEnvelope, error) {
	return c.DoWithHeaders(ctx, path, request, HTTPControlPlaneRequestHeaders{})
}

func (c *HTTPControlPlane) DoWithHeaders(ctx context.Context, path string, request ServerRequestEnvelope, extra HTTPControlPlaneRequestHeaders) (ServerResponseEnvelope, error) {
	if c == nil || c.baseURL == nil || !strings.HasPrefix(path, "/") {
		return ServerResponseEnvelope{}, errors.New("invalid control-plane client or path")
	}
	endpoint := *c.baseURL
	endpoint.Path = strings.TrimRight(c.baseURL.Path, "/") + path
	body, err := json.Marshal(request)
	if err != nil {
		return ServerResponseEnvelope{}, err
	}
	httpRequest, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint.String(), bytes.NewReader(body))
	if err != nil {
		return ServerResponseEnvelope{}, err
	}
	httpRequest.Header.Set("content-type", "application/json")
	if c.credentialProof != "" {
		httpRequest.Header.Set("x-ci-scope-credential-proof", c.credentialProof)
	}
	if extra.Authorization != "" {
		httpRequest.Header.Set("authorization", extra.Authorization)
	}
	if extra.EnrollmentIssuer != "" {
		httpRequest.Header.Set("x-ci-scope-enrollment-issuer", extra.EnrollmentIssuer)
	}
	response, err := c.client.Do(httpRequest)
	if err != nil {
		return ServerResponseEnvelope{}, err
	}
	defer response.Body.Close()
	responseBody, err := io.ReadAll(io.LimitReader(response.Body, maxServerResponseBytes+1))
	if err != nil {
		return ServerResponseEnvelope{}, err
	}
	if int64(len(responseBody)) > maxServerResponseBytes {
		return ServerResponseEnvelope{}, errors.New("control-plane response is too large")
	}
	return decodeControlPlaneResponse(response, responseBody, request)
}
