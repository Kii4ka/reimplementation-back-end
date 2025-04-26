require 'rails_helper'

RSpec.describe ApplicationController, type: :controller do
  # Create a test controller that inherits from ApplicationController
  # This anonymous controller allows testing ApplicationController functionality directly
  controller do
    before_action :set_locale
    before_action :authorize
    
    def index
      render plain: 'test controller'
    end
  end

  # Configure routes for testing so we can make HTTP requests to our anonymous controller
  before do
    routes.draw do
      get 'index' => 'anonymous#index'
    end
  end

  describe '#set_locale' do
    before do
      # Store original values to restore after tests - prevents test interdependence
      @original_locales = I18n.available_locales
      @original_default_locale = I18n.default_locale

      # Configure available locales for testing with a predictable set
      I18n.available_locales = [:en, :fr, :es]
      I18n.default_locale = :en
    end

    after do
      # Restore original values to avoid affecting other tests
      I18n.available_locales = @original_locales
      I18n.default_locale = @original_default_locale
    end

    it 'ignores invalid locales in params' do
      # Tests that invalid locale parameters are safely ignored
      # and the system falls back to the default locale
      allow(controller).to receive(:authorize).and_return(true)
      
      get :index, params: { locale: 'invalid' }
      expect(I18n.locale).to eq(:en) # Should fall back to default
    end

    it 'uses default locale when no valid locale is found' do
      # Tests fallback behavior when Accept-Language header contains
      # only locales that aren't supported by our application
      allow(controller).to receive(:authorize).and_return(true)
      
      request.env['HTTP_ACCEPT_LANGUAGE'] = 'de-DE,de;q=0.9' # Not in available_locales
      get :index
      expect(I18n.locale).to eq(:en) # Default locale
    end
  end

  describe '#extract_locale' do
    before do
      @original_locales = I18n.available_locales
      I18n.available_locales = [:en, :fr, :es]
      
      # Stub authorize for all tests in this context
      allow(controller).to receive(:authorize).and_return(true)
    end

    after do
      I18n.available_locales = @original_locales
    end

    it 'extracts locale from params' do
      # Tests that locale is correctly extracted from URL parameters
      # URL parameters take precedence over browser settings
      get :index, params: { locale: 'fr' }
      expect(controller.send(:extract_locale)).to eq(:fr)
    end

    it 'returns nil for invalid locales in params' do
      # Tests that invalid locales in URL parameters are rejected
      # and extract_locale returns nil so fallback mechanisms can be used
      get :index, params: { locale: 'invalid' }
      expect(controller.send(:extract_locale)).to be_nil
    end

    it 'extracts first valid locale from Accept-Language header' do
      # Tests extraction of locale from the Accept-Language HTTP header
      # The first valid locale in the preference list should be selected
      request.env['HTTP_ACCEPT_LANGUAGE'] = 'fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7'
      get :index
      expect(controller.send(:extract_locale)).to eq(:fr)
    end

    it 'extracts second valid locale from Accept-Language header if first is invalid' do
      # Tests that if the first locale in Accept-Language isn't available,
      # the system correctly falls back to the next valid locale in the list
      request.env['HTTP_ACCEPT_LANGUAGE'] = 'de-DE,de;q=0.9,es-ES;q=0.8,es;q=0.7'
      get :index
      expect(controller.send(:extract_locale)).to eq(:es)
    end

    it 'returns nil when Accept-Language header contains no valid locales' do
      # Tests behavior when no locales in the Accept-Language header
      # match our application's available locales
      request.env['HTTP_ACCEPT_LANGUAGE'] = 'de-DE,de;q=0.9'
      get :index
      expect(controller.send(:extract_locale)).to be_nil
    end

    it 'handles empty Accept-Language headers gracefully' do
      # Tests that empty Accept-Language headers don't cause errors
      # and the method gracefully returns nil
      request.env['HTTP_ACCEPT_LANGUAGE'] = ''
      get :index
      expect(controller.send(:extract_locale)).to be_nil
    end

    it 'handles nil Accept-Language headers gracefully' do
      # Tests that missing Accept-Language headers don't cause errors
      # and the method gracefully returns nil
      request.env.delete('HTTP_ACCEPT_LANGUAGE')
      get :index
      expect(controller.send(:extract_locale)).to be_nil
    end
  end

  describe 'language code extraction' do
    before do
      # Stub authorize for all tests in this context
      allow(controller).to receive(:authorize).and_return(true)
    end
    
    it 'correctly extracts country-specific language codes' do
      # Tests that language is correctly extracted from country-specific codes
      # For example, en-US should be recognized as en
      request.env['HTTP_ACCEPT_LANGUAGE'] = 'en-US,en;q=0.9'
      expect(controller.send(:extract_locale)).to eq(:en)
    end

    it 'correctly handles multi-part language headers' do
      # Tests parsing of complex Accept-Language headers with multiple languages
      # and country variants, ensuring the highest priority valid language is selected
      request.env['HTTP_ACCEPT_LANGUAGE'] = 'fr-CA,fr;q=0.9,en-US;q=0.8,en;q=0.7,es;q=0.6'
      expect(controller.send(:extract_locale)).to eq(:fr)
    end

    it 'correctly handles language headers with quality factors' do
      # Tests parsing of Accept-Language headers with explicit quality factors
      # The highest quality valid language should be selected
      I18n.available_locales = [:en, :fr, :es]
      request.env['HTTP_ACCEPT_LANGUAGE'] = 'de;q=1.0,fr;q=0.9,en;q=0.8'
      expect(controller.send(:extract_locale)).to eq(:fr)
    end
  end
end
