describe("Web site availability", () => {
  let createdEmployeeUrl;

  after(() => {
    if (createdEmployeeUrl) {
      cy.request("DELETE", createdEmployeeUrl)
        .its("status")
        .should("eq", 200);
    }
  });

  it("Sanity listings web site", () => {
    cy.visit("/");
    cy.contains("Create Record").should("exist");
  });

  it("Test Adding Employee listings", () => {
    cy.intercept("POST", "**/record").as("createEmployee");
    cy.intercept("GET", "**/record/").as("listEmployees");

    cy.visit("/create");
    cy.get("#name").type("Employee1");
    cy.get("#position").type("Position1");
    cy.get("#positionIntern").click({ force: true });
    cy.contains("Create person").click({ force: true });

    cy.wait("@createEmployee").then(({ request, response }) => {
      expect(response?.statusCode, "Create employee response status").to.eq(200);

      const { insertedId } = response.body;
      expect(insertedId, "Created employee ID").to.be.a("string").and.not.be.empty;

      createdEmployeeUrl = `${request.url}/${insertedId}`;
    });

    cy.visit("/records");

    cy.wait("@listEmployees")
      .its("response.statusCode")
      .should("eq", 200);

    cy.contains("td", "Employee1").should("be.visible");
  });
});