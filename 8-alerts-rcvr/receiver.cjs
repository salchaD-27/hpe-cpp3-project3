const express = require('express');

const app = express();
const PORT = 5001;

app.use(express.json());

const alertHistory = [];

app.post('/alerts', (req, res) => {
  console.log('\n' + '='.repeat(60));
  console.log(`ALERT RECEIVED at ${new Date().toISOString()}`);
  console.log('='.repeat(60));
  
  const data = req.body;
  
  // Alertmanager sends a webhook payload with an 'alerts' array
  if (data && data.alerts && Array.isArray(data.alerts)) {
    data.alerts.forEach((alert, index) => {
      const labels = alert.labels || {};
      const annotations = alert.annotations || {};
      
      console.log(`\nAlert #${index + 1}:`);
      console.log(`   Name: ${labels.alertname || 'Unknown'}`);
      console.log(`   Severity: ${labels.severity || 'Unknown'}`);
      console.log(`   Status: ${alert.status || 'firing'}`);
      console.log(`   Starts At: ${alert.startsAt || 'N/A'}`);
      console.log(`   Summary: ${annotations.summary || 'No summary'}`);
      console.log(`   Description: ${annotations.description || 'No description'}`);
      console.log(`   Stats Result: ${labels.stats_result || 'N/A'}`);
    });
    
    // Store in history
    alertHistory.push({
      timestamp: new Date().toISOString(),
      groupLabels: data.groupLabels,
      commonLabels: data.commonLabels,
      alerts: data.alerts,
      totalAlerts: data.alerts.length
    });
  } 
  // Handle older format or direct alert
  else if (data.labels) {
    console.log(`\n📢 Alert:`);
    console.log(`   Name: ${data.labels.alertname || 'Unknown'}`);
    console.log(`   Severity: ${data.labels.severity || 'Unknown'}`);
    console.log(`   Status: ${data.status || 'firing'}`);
    console.log(`   Description: ${data.annotations?.description || 'No description'}`);
    
    alertHistory.push({
      timestamp: new Date().toISOString(),
      alerts: [data],
      totalAlerts: 1
    });
  }
  else {
    console.log('\n📢 Received unknown payload format:');
    console.log(JSON.stringify(data, null, 2));
    alertHistory.push({
      timestamp: new Date().toISOString(),
      rawPayload: data,
      totalAlerts: 0
    });
  }
  
  console.log('\n' + '='.repeat(60));
  
  res.status(200).json({ 
    status: 'received', 
    timestamp: new Date().toISOString(),
    alertsReceived: data.alerts ? data.alerts.length : 1
  });
});

app.get('/alerts', (req, res) => {
  const limit = req.query.limit ? parseInt(req.query.limit) : 50;
  const recentAlerts = alertHistory.slice(-limit);
  
  res.json({
    totalAlertsReceived: alertHistory.length,
    recentAlerts: recentAlerts.reverse(),
    lastAlertAt: alertHistory.length > 0 ? alertHistory[alertHistory.length - 1].timestamp : null
  });
});

app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    timestamp: new Date().toISOString(),
    totalAlertsReceived: alertHistory.length,
    uptime: process.uptime()
  });
});

app.delete('/alerts', (req, res) => {
  const cleared = alertHistory.length;
  alertHistory.length = 0;
  res.json({ 
    message: `Cleared ${cleared} alerts from history`, 
    timestamp: new Date().toISOString() 
  });
});

app.listen(PORT, () => {
  console.log(`✅ Alert receiver running at http://localhost:${PORT}`);
  console.log(`   POST /alerts - Webhook endpoint`);
  console.log(`   GET  /alerts - View history`);
  console.log(`   GET  /health - Health check`);
  console.log(`\n📡 Waiting for alerts from Alertmanager...\n`);
});