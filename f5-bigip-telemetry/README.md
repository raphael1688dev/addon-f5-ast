# F5 BIG-IP Telemetry

**Setup Instructions:**
1. Install this Add-on.
2. Go to the **Configuration** tab.
3. Set your F5 IP address.
4. **IMPORTANT:** You MUST enable at least one module (e.g., check `enable_system` and `enable_ltm`), otherwise no data will be collected.
5. Start the Add-on.
6. Configure Prometheus to scrape port `8888` of this container.
