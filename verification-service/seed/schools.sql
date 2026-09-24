-- Starter registry: the schools already referenced in the app
-- (UserProfileModel-6)Models.swift:169) so nothing regresses on day one.
--
-- This is a seed, not the nationwide list. See seed/README.md for bulk import.

INSERT OR REPLACE INTO schools (id, name, short_name, state, enabled) VALUES
    ('ut-austin',  'The University of Texas at Austin', 'UT Austin',  'TX', 1),
    ('berkeley',   'University of California, Berkeley', 'UC Berkeley', 'CA', 1),
    ('umich',      'University of Michigan',            'UMich',      'MI', 1),
    ('calpoly-slo','California Polytechnic State University, San Luis Obispo', 'Cal Poly SLO', 'CA', 1),
    ('usc',        'University of Southern California', 'USC',        'CA', 1),
    ('nyu',        'New York University',               'NYU',        'NY', 1),
    ('depaul',     'DePaul University',                 'DePaul',     'IL', 1);

INSERT OR REPLACE INTO school_domains (domain, school_id, kind) VALUES
    ('utexas.edu',        'ut-austin',   'student'),
    ('alumni.utexas.edu', 'ut-austin',   'alumni'),
    -- Berkeley issues @berkeley.edu to students; department subdomains
    -- (eecs.berkeley.edu, etc.) resolve through it via `domainCandidates`.
    ('berkeley.edu',      'berkeley',    'student'),
    ('umich.edu',         'umich',       'student'),
    ('calpoly.edu',       'calpoly-slo', 'student'),
    ('usc.edu',           'usc',         'student'),
    ('nyu.edu',           'nyu',         'student'),
    ('depaul.edu',        'depaul',      'student');
