import React, { useEffect, useState } from "react";

const API_BASE_URL =
  process.env.REACT_APP_API_BASE_URL || "http://localhost:5050";

export default function HealthStatus() {
  const [status, setStatus] = useState([]);

  useEffect(() => {
    fetch(`${API_BASE_URL}/healthcheck/`)
      .then((response) => response.json())
      .then((data) => setStatus(data));
  }, []);

  return (
    <div>
      <h3>API Status</h3>
      {JSON.stringify(status)}
    </div>
  );
}