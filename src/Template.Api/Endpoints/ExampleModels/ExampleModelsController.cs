using CcAcca.LogDimensionCollection.AspNetCore;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Template.Shared.Data;
using Template.Shared.Model;

namespace Template.Api.Endpoints.ExampleModels {
  [Route("api/[controller]")]
  [ApiController]
  [ProducesResponseType(StatusCodes.Status401Unauthorized)]
  public class ExampleModelsController : ControllerBase {
    private AppDatabase Db { get; }

    public ExampleModelsController(AppDatabase db) {
      Db = db;
    }

    [HttpGet]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<IEnumerable<ExampleModel>> List() {
      return await Db.Examples.ToListAsync();
    }

    [HttpGet("{id}")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ExampleModel?> Get(Guid id) {
      // note: if no match is found, this action will return a 404
      return await Db.Examples.SingleOrDefaultAsync(x => x.Id == id);
    }

    [HttpDelete("{id}")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Delete(Guid id) {
      Db.Examples.Remove(new ExampleModel { Id = id });
      try {
        await Db.SaveChangesAsync();
      }
      catch (DbUpdateConcurrencyException) {
        // the record did not exist
        return NotFound();
      }

      return Ok();
    }

    [HttpPost]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ExampleModel), StatusCodes.Status201Created)]
    [CollectActionArgs]
    public async Task<IActionResult> Create(ExampleModel model) {
      // IMPORTANT: You might want to consider accepting a different `model` class for POST/PUT scenarios
      // and mapping this input model classes to your entities.
      // In which case consider using AutoMapper for those cases where the Entity-to-DTO property names are largely
      // one-to-one

      if (!ModelState.IsValid) {
        return BadRequest(ModelState);
      }

      Db.Examples.Add(model);
      await Db.SaveChangesAsync();

      return Created(string.Empty, model);
    }

    [HttpPut("{id}")]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ExampleModel), StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [CollectActionArgs]
    public async Task<IActionResult> Update(Guid id, ExampleModel model) {
      // IMPORTANT: You might want to consider accepting a different `model` class for POST/PUT scenarios
      // and mapping this input model classes to your entities.
      // In which case consider using AutoMapper for those cases where the Entity-to-DTO property names are largely
      // one-to-one

      if (!ModelState.IsValid) {
        return BadRequest(ModelState);
      }

      // creating OR updating makes this endpoint idempotent
      model.Id = id;
      var exists = await Db.Examples.AnyAsync(x => x.Id == id);
      if (exists) {
        Db.Examples.Update(model);
      } else {
        Db.Examples.Add(model);
      }

      await Db.SaveChangesAsync();

      return exists ? NoContent() : Created(string.Empty, model);
    }
  }
}