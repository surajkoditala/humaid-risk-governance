import sys; sys.path.insert(0, '.')
from ado import upload, create, ORG
BASE = 'https://ca-gh-hrg-workbench-dev.jollyplant-1cbb4459.eastus2.azurecontainerapps.io'
ENV = f'<p><b>Environment:</b> deployed dev Workbench ({BASE}), release/1.00 @ 6112122, Chrome desktop 1440x900. Found by exploratory testing on 28 Sep 2026.</p>'
def wi(i): return {'rel': 'System.LinkTypes.Related', 'url': f'{ORG}/_apis/wit/workItems/{i}'}
def parent(i): return {'rel': 'System.LinkTypes.Hierarchy-Reverse', 'url': f'{ORG}/_apis/wit/workItems/{i}'}
def att(path, name, comment): return {'rel': 'AttachedFile', 'url': upload(path, name), 'attributes': {'comment': comment}}

bugs = [
 dict(
  title='DEF-034 - Long request title pushes the following columns and row actions off screen in list tables',
  sev='3 - Medium', pri=2, tag='Intake', parent=1, related=[4, 20, 25, 116],
  repro=ENV + '''
<p><b>Steps to reproduce:</b></p><ol>
<li>Open the app, click <i>Continue without signing in</i>, switch to <b>Priya Owens - ProductOwner</b>.</li>
<li>Submit Request: type Vendor, a realistic long title (about 200 characters, e.g. "Onboard QuickPay Processing Ltd (Malta) as the card settlement processor for the consumer debit and prepaid card programmes, including cardholder PII and daily settlement file exchange over API"), any description, any linked record. Submit.</li>
<li>Open <b>My Requests</b>.</li>
<li>Switch to <b>Amara Chen - Analyst</b> and open <b>Assessments</b>.</li>
<li>Finalize and route the request (possible because of DEF-001), switch to <b>Jordan Blake - CommitteeMember</b> and open <b>Committee Queue</b>.</li>
</ol>
<p><b>Expected:</b> Long titles wrap (or are truncated with an ellipsis and the full title in a tooltip). Every column and the row action (Open / Review) stay visible at desktop width without horizontal scrolling.</p>
<p><b>Actual:</b></p><ul>
<li><b>Assessments</b> (CR-2026-00092): the Status and Days columns and the <b>Open</b> button sit off screen. The table is 992 px wide but its content is 181,367 px wide; the Open button is at x = 181,695 px. The analyst sees only Request #, Type and Title, with no visible hint that there are more columns.</li>
<li><b>My Requests</b>: the Status and Days columns sit off screen (content 181,297 px in a 992 px table).</li>
<li><b>Committee Queue</b>: the <b>Review</b> button sits off screen (content 1,645 px in a 992 px table), caused by the 200-character title alone.</li>
<li>To reach the columns the user must scroll to the bottom of the table, where the horizontal scrollbar is, and drag right.</li>
<li>One long title breaks the list for <b>every</b> user, not just its owner: on the shared dev database, CR-2026-00088 (a 20,000-character title accepted because of DEF-009 / bug 116) makes My Requests and Assessments 181,000 px wide for everyone.</li></ul>
<p><b>Root cause:</b> the shared table component sets <code>whitespace-nowrap</code> on every cell (webapp/src/components/ui/table.jsx, TableCell and TableHead), and the Title cell in MyRequests.jsx, AnalystInbox.jsx and CommitteeQueue.jsx has no width limit or wrapping, so the table grows to the longest title and the wrapper scrolls horizontally (overflow-x-auto).</p>
<p><b>Suggested fix:</b> on the Title cell use <code>whitespace-normal break-words</code> with a max width (or <code>max-w-[..] truncate</code> plus <code>title={r.title}</code>), keep the action column narrow and always visible (e.g. sticky right), and enforce a title length limit server-side (bug 116).</p>''',
  ac='<ul><li>Given a request with a 200-character title, when My Requests, Assessments or Committee Queue is shown at 1440 px, then all columns and the Open / Review action are visible without horizontal scrolling.</li><li>Given a title longer than the available width, when it is shown in a list, then it wraps or is truncated with the full title available on hover.</li><li>Given one request with an extremely long title, when any user opens a list, then the other rows and columns still lay out normally.</li></ul>',
  files=[('ux/assessments.png', 'assessments-open-column-off-screen.png', 'Assessments: Status, Days and Open off screen'),
         ('ux/my-requests.png', 'my-requests-status-off-screen.png', 'My Requests: Status and Days off screen'),
         ('ux/committee-queue.png', 'committee-queue-review-off-screen.png', 'Committee Queue: Review off screen'),
         ('ux/assessments-bottom.png', 'assessments-bottom-no-scroll-hint.png', 'Bottom of Assessments: no visible hint of more columns')]),
 dict(
  title='DEF-025 - User switcher cuts off the role name ("CommitteeM", "ProductOwne")',
  sev='4 - Low', pri=3, tag='Governance', parent=34, related=[37],
  repro=ENV + '''
<p><b>Steps to reproduce:</b></p><ol>
<li>Open the app and click <i>Continue without signing in</i>.</li>
<li>In the user switcher (top left of the header) select <b>Jordan Blake - CommitteeMember</b>.</li>
<li>Select <b>Priya Owens - ProductOwner</b>.</li></ol>
<p><b>Expected:</b> The switcher shows the full "name - role" label, or truncates with an ellipsis and shows the full label on hover, so the user can tell which role they are acting as.</p>
<p><b>Actual:</b> The label is clipped with no ellipsis or tooltip: "Jordan Blake - CommitteeM" (text needs 221 px, 182 px available) and "Priya Owens - ProductOwne" (186 px needed, 182 px available). "Amara Chen - Analyst" fits. The role is the part that gets cut, and the role is what decides which screens and actions the user has.</p>
<p><b>Root cause:</b> the switcher's SelectTrigger has a fixed width (<code>w-40 sm:w-56</code>, webapp/src/App.jsx:39) and the value text has no <code>truncate</code> / <code>title</code>.</p>
<p><b>Suggested fix:</b> let the trigger size to its content (<code>w-auto min-w-56</code>), or add <code>truncate</code> plus a <code>title</code> with the full label; alternatively show the role as a separate badge.</p>
<p><b>Note:</b> first recorded as DEF-025 (exploratory) in docs/qa/test-execution-report.</p>''',
  ac='<ul><li>Given any seeded user, when they are selected in the switcher at 1440 px, then the full name and role are readable, or the label ends with an ellipsis and the full label shows on hover.</li></ul>',
  files=[('ux/committee-queue.png', 'switcher-committeemember-cut.png', 'Header: "Jordan Blake - CommitteeM"'),
         ('ux/switcher-options.png', 'switcher-options-full-labels.png', 'Open switcher list showing the full labels')]),
]
for b in bugs:
    rels = [parent(b['parent'])] + [wi(i) for i in b['related']] + [att(p, n, c) for p, n, c in b['files']]
    out = create({'System.Title': b['title'], 'Microsoft.VSTS.TCM.ReproSteps': b['repro'], 'Microsoft.VSTS.Common.AcceptanceCriteria': b['ac'],
                  'Microsoft.VSTS.Common.Severity': b['sev'], 'Microsoft.VSTS.Common.Priority': b['pri'], 'System.Tags': b['tag']}, rels)
    print(out['id'], b['title'], len(out.get('relations', [])), 'relations')
