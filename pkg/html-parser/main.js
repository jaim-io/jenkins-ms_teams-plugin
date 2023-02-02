const jsdom = require("jsdom");
const { JSDOM } = jsdom;
const fs = require("fs");
const path = require("path");

const settingsFile = "../../appsettings.json";
if (!fs.existsSync(settingsFile)) {
  const obj = {
    "parser": {
      "separator": "<SEP>",
      "endOfRow": "<EOR>"
    }
  }

  fs.writeFileSync(settingsFile, JSON.stringify(obj, null, 2), "utf-8")
}
const settings = require(settingsFile)


const getJobData = (document) => {
  let result = "";
  document.querySelectorAll("tr").forEach((e) => {
    if (e.id.includes("job_")) {
      if (result !== "") {
        result += settings.parser.endOfRow;
      }

      let row = `${e.id}`
      let count = 0;

      const tdTags = e.querySelectorAll("td");
      tdTags.forEach((td) => {
        let data = td.getAttribute("data");
        if (data && (data.includes("2022") || data === "-")) {
          row += `${settings.parser.separator}${data !== "-" ? data : ""}`
          count++;
        }
      });
      result += row;
    }
  });
  return result;
};


fs.readFile(path.resolve(__dirname, "../../temp"), "utf8", (err, data) => {
  if (err) {
    console.error(err);
    return;
  }

  const { document } = (new JSDOM(data)).window;
  const result = getJobData(document);

  // Output result to STDOUT
  console.log(result);
})
