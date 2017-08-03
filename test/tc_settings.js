requirejs(['qunit', 'jquery', 'settings'], function (QUnit, $, Settings) {

  QUnit.module('settings');

  QUnit.test('settings.load', function(assert) {
      var done = assert.async(1);
      var data = {'key': 'value', 'key2': 'value2'};
      var name = 'key';
      var expected = data[name];
      var settings = new Settings();
      property = settings.getProperty('key2');
      property.addListener('change', function (triggeredValue) {
        assert.equal(triggeredValue, 'value2', 'Loading settings should trigger the "change" event on overwritten properties.');
        done();
      });
      settings.load(data);
      var actual = settings.get(name);
      assert.equal(actual, expected, 'It should return the loaded value.');
  });

  QUnit.test('settings.get, settings.getProperty', function(assert) {
      var data = {'key': 'value', 'key2': 'value2'};
      var name = 'key';
      var expected = data[name];
      var settings = new Settings().load(data);
      var property = settings.getProperty(name);
      assert.equal(settings.get(name), expected);
      assert.equal(property.getValue(), expected);
      assert.equal(settings.get(name), property.getValue());
  });

  QUnit.test('settings.set', function(assert) {
      assert.expect(5);
      var done = assert.async(2);
      var data = {'key5': 'value', 'key2': 'value2'};
      var name = 'key5';
      var expectedValue = 'changed value';
      var settings = new Settings().load(data);
      var property = settings.getProperty(name);
      settings.addListener('change', function (triggeredName, triggeredValue) {
        assert.equal(triggeredName,  name,          'settings.set should trigger "changed" on settings');
        assert.equal(triggeredValue, expectedValue, 'settings.set should trigger "changed" on settings');
        done();
      });
      property.addListener('change', function (triggeredValue) {
        assert.equal(triggeredValue, expectedValue, 'settings.set should trigger "changed" on property');
        done();
      });
      settings.set(name, expectedValue);
      assert.equal(settings.get(name), expectedValue);
      assert.equal(property.getValue(), expectedValue);
  });

  QUnit.test('property.setValue', function(assert) {
      assert.expect(5);
      var done = assert.async(2);
      var data = {'key': 'value3', 'key2': 'value2'};
      var name = 'key';
      var expectedValue = 'changed value3';
      var settings = new Settings().load(data);
      var property = settings.getProperty(name);
      settings.addListener('change', function (triggeredName, triggeredValue) {
        assert.equal(triggeredName,  name,          'property.setValue should trigger "changed" on settings');
        assert.equal(triggeredValue, expectedValue, 'property.setValue should trigger "changed" on settings');
        done();
      });
      property.addListener('change', function (triggeredValue) {
        assert.equal(triggeredValue, expectedValue, 'property.setValue should trigger "changed"');
        done();
      });
      property.setValue(expectedValue);
      assert.equal(settings.get(name), expectedValue);
      assert.equal(property.getValue(), expectedValue);
  });

});
