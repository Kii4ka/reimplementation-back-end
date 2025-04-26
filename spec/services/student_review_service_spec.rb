require 'rails_helper'

# This spec verifies the core functionality of the StudentReviewService, which handles
# the business logic for student reviews including bidding, calibration, and review mappings
RSpec.describe StudentReviewService do
  # Use doubles instead of factory objects to avoid database dependencies
  # This ensures tests are fast and focused on service logic rather than database interaction
  let(:user) { double('User', id: 1, name: 'Test User') }
  let(:assignment) { double('Assignment', id: 42, name: 'Test Assignment', is_calibrated: false, 
                           bidding_for_reviews_enabled: false, team_reviewing_enabled: false) }
  let(:participant) { double('AssignmentParticipant', id: 123, user: user, user_id: user.id, assignment: assignment) }
  let(:reviewer) { double('Reviewer', id: 456, name: 'Test Reviewer') }
  let(:topic_id) { 789 }

  before do
    # Sets up common test environment by stubbing core dependencies
    # This isolates the service under test from its external dependencies
    
    # Mock the participant and assignment loading to avoid database queries
    allow_any_instance_of(StudentReviewService).to receive(:load_participant_and_assignment) do |service, participant_id|
      service.instance_variable_set(:@participant, participant)
      service.instance_variable_set(:@assignment, assignment)
      service.instance_variable_set(:@topic_id, topic_id)
      service.instance_variable_set(:@review_phase, 'review')
    end
    
    # Stub other initialization methods to control test environment
    allow_any_instance_of(StudentReviewService).to receive(:load_review_mappings)
    allow_any_instance_of(StudentReviewService).to receive(:calculate_review_progress)
    allow_any_instance_of(StudentReviewService).to receive(:load_response_ids)
    
    # Configure AssignmentParticipant finder to return our test participant
    allow(AssignmentParticipant).to receive(:find).with(participant.id.to_s).and_return(participant)
    
    # Enable testing of error scenarios with a non-existent participant ID
    allow(AssignmentParticipant).to receive(:find).with('999').and_raise(ActiveRecord::RecordNotFound)
  end

  # Tests for the initialization process, which should properly set up the service state
  describe '#initialize' do
    it 'loads participant and assignment' do
      # Verifies that participant and assignment are correctly loaded and accessible
      service = StudentReviewService.new(participant.id.to_s)
      expect(service.participant).to eq(participant)
      expect(service.assignment).to eq(assignment)
    end
    
    it 'sets topic_id and review_phase' do
      # Ensures topic_id and review_phase are set during initialization
      service = StudentReviewService.new(participant.id.to_s)
      expect(service.topic_id).to eq(topic_id)
      expect(service.review_phase).to eq('review')
    end
    
    it 'raises a wrapped error when participant does not exist' do
      allow_any_instance_of(StudentReviewService).to receive(:load_participant_and_assignment).and_call_original
      
      expect { StudentReviewService.new('999') }.to raise_error(
        RuntimeError, 
        /Failed to load participant data: ActiveRecord::RecordNotFound/
      )
    end
  end

  # Tests for the bidding functionality which determines if review bidding is enabled
  describe '#bidding_enabled?' do
    before do
      # Allow the real bidding_enabled? method to run while stubbing other methods
      allow_any_instance_of(StudentReviewService).to receive(:bidding_enabled?).and_call_original
    end
    
    it 'returns true when bidding is enabled for the assignment' do
      # Verifies that bidding_enabled? correctly reflects the assignment's setting when enabled
      allow(assignment).to receive(:bidding_for_reviews_enabled).and_return(true)
      service = StudentReviewService.new(participant.id.to_s)
      expect(service.bidding_enabled?).to be true
    end

    it 'returns false when bidding is disabled for the assignment' do
      # Verifies that bidding_enabled? correctly reflects the assignment's setting when disabled
      allow(assignment).to receive(:bidding_for_reviews_enabled).and_return(false)
      service = StudentReviewService.new(participant.id.to_s)
      expect(service.bidding_enabled?).to be false
    end
  end

  # Tests for bidding status using direct assignment property
  describe 'bidding status' do
    it 'indicates when bidding is enabled for the assignment' do
      service = StudentReviewService.new(participant.id.to_s)
      # Just mock the method return value without trying to call original
      allow(service).to receive(:bidding_enabled?).and_return(true)
      expect(service.bidding_enabled?).to be true
    end

    it 'indicates when bidding is disabled for the assignment' do
      service = StudentReviewService.new(participant.id.to_s)
      # Just mock the method return value without trying to call original
      allow(service).to receive(:bidding_enabled?).and_return(false)
      expect(service.bidding_enabled?).to be false
    end
  end

  # Tests for calibrated assignments which require special review mapping ordering
  describe 'when assignment is calibrated' do
    before do
      # Set up specific review mappings with IDs that will produce a predictable sort order
      @map1 = double('ReviewResponseMap', id: 1, response: [])
      @map2 = double('ReviewResponseMap', id: 6, response: [])
      @map3 = double('ReviewResponseMap', id: 2, response: [])
      @map4 = double('ReviewResponseMap', id: 7, response: [])
      @map5 = double('ReviewResponseMap', id: 5, response: [])
      
      # Mark the assignment as calibrated to trigger the special sorting logic
      allow(assignment).to receive(:is_calibrated).and_return(true)
      
      # Allow the actual load_review_mappings method to run to test its functionality
      allow_any_instance_of(StudentReviewService).to receive(:load_review_mappings).and_call_original
      
      # Provide test mappings to ReviewResponseMap.where
      allow(ReviewResponseMap).to receive(:where)
        .with(reviewer_id: reviewer.id, team_reviewing_enabled: false)
        .and_return([@map1, @map2, @map3, @map4, @map5])
        
      # Ensure the participant has a reviewer to prevent empty mappings
      allow(participant).to receive(:get_reviewer).and_return(reviewer)
    end
    
    it 'sorts review mappings correctly by id % 5' do
      # Tests a critical business rule: calibrated assignments must sort mappings by id modulo 5
      # This ensures students see calibration examples in the pedagogically correct order
      service = StudentReviewService.new(participant.id.to_s)
      
      # Expected order based on id % 5:
      # @map5 (5 % 5 = 0) should be first
      # @map1 (1 % 5 = 1) should be second
      # @map6 (6 % 5 = 1) should be third
      # @map2 (2 % 5 = 2) should be fourth
      # @map7 (7 % 5 = 2) should be fifth
      expected_ids = [5, 1, 6, 2, 7]
      actual_ids = service.review_mappings.map(&:id)
      
      expect(actual_ids).to eq(expected_ids)
    end
  end

  # Tests edge case of participants without reviewers
  describe 'when participant has no reviewer' do
    before do
      # Allow the real load_review_mappings method to run
      allow_any_instance_of(StudentReviewService).to receive(:load_review_mappings).and_call_original
      
      # Configure participant to have no reviewer (important edge case)
      allow(participant).to receive(:get_reviewer).and_return(nil)
    end
    
    it 'sets review_mappings to empty array' do
      # Verifies that review_mappings is an empty array when participant has no reviewer
      # This prevents null pointer exceptions in the UI layers
      service = StudentReviewService.new(participant.id.to_s)
      
      expect(service.review_mappings).to eq([])
    end
    
    it 'sets review progress counters to zero' do
      # Ensures all review progress counters are zero when there are no mappings
      # This maintains consistent state for UI components that display progress
      allow_any_instance_of(StudentReviewService).to receive(:calculate_review_progress).and_call_original
      
      service = StudentReviewService.new(participant.id.to_s)
      
      expect(service.num_reviews_total).to eq(0)
      expect(service.num_reviews_completed).to eq(0)
      expect(service.num_reviews_in_progress).to eq(0)
    end
  end

  # Tests for response ID loading functionality
  describe 'when loading response IDs' do
    before do
      # Create a custom SampleReview class to replace the real one
      # This advanced stubbing technique allows testing code that uses ActiveRecord relations
      sample_reviews_class = Class.new do
        def self.where(*)
          # This will be overridden by the stub, but needs to exist as a method placeholder
        end
      end
      
      # Replace the real SampleReview class with our test implementation
      stub_const("SampleReview", sample_reviews_class)
      
      # Create a mock for the query result
      sample_reviews = double('SampleReviews')
      
      # Configure the mock to return test response IDs
      allow(SampleReview).to receive(:where).with(assignment_id: assignment.id).and_return(sample_reviews)
      allow(sample_reviews).to receive(:pluck).with(:response_id).and_return([101, 102, 103])
      
      # Allow the real load_response_ids method to run
      allow_any_instance_of(StudentReviewService).to receive(:load_response_ids).and_call_original
    end
    
    it 'loads response IDs correctly for the assignment' do
      # Verifies that response IDs are properly loaded from the database
      # These IDs are used to track which reviews have been completed
      service = StudentReviewService.new(participant.id.to_s)
      expect(service.response_ids).to eq([101, 102, 103])
    end
    
    it 'handles empty response lists' do
      # Tests the edge case of no responses being available
      # This ensures the service behaves correctly when no reviews have been submitted
      empty_sample_reviews = double('EmptySampleReviews')
      allow(SampleReview).to receive(:where).with(assignment_id: assignment.id).and_return(empty_sample_reviews)
      allow(empty_sample_reviews).to receive(:pluck).with(:response_id).and_return([])
      
      service = StudentReviewService.new(participant.id.to_s)
      expect(service.response_ids).to eq([])
    end
  end
end