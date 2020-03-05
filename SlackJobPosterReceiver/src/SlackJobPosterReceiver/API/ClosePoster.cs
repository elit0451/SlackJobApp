using System;
using System.Net.Http;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;

namespace SlackJobPosterReceiver.API
{
    public class ClosePoster
    {
        private readonly HttpClient _client;

        public ClosePoster(HttpClient client = null)
        {
            _client = client ?? new HttpClient();
        }

        public async Task<JObject> PostLead(string leadName)
        {
            JObject leadObj = new JObject
            {
                ["name"] = leadName
            };

            HttpResponseMessage response = await _client.PostAsJsonAsync("https://api.close.com/api/v1/lead/", leadObj, GlobalVars.CLOSE_TOKEN);

            return await response.Content.ReadAsJsonAsync<JObject>();
        }

        public async Task<JObject> PostOpportunity(string msgHeader, string leadId, string opportunityStatusName)
        {
            string statusId = await GetStatusId(opportunityStatusName);
            GlobalVars.CONTEXT.Logger.LogLine(statusId);

            JObject opportunityObj = new JObject
            {
                ["note"] = msgHeader,
                ["lead_id"] = leadId,
                ["confidence"] = 0
            };

            if (string.IsNullOrEmpty(statusId))
                opportunityObj.Add("status_id", statusId);

            HttpResponseMessage response = await _client.PostAsJsonAsync("https://api.close.com/api/v1/opportunity/", opportunityObj, GlobalVars.CLOSE_TOKEN);

            return await response.Content.ReadAsJsonAsync<JObject>();
        }

        public async Task<string> GetStatusId(string statusName)
        {
            HttpResponseMessage response = await _client.GetAsJsonAsync("https://api.close.com/api/v1/status/opportunity/");
            JObject responseJObj = await response.Content.ReadAsJsonAsync<JObject>();

            string statusId = (string)responseJObj.SelectToken($"$..data[?(@.label=='{statusName}')].id");

            return statusId;
        }
    }
}