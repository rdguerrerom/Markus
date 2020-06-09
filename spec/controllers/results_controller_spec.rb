describe ResultsController do
  let(:assignment) { create :assignment }
  let(:student) { create :student, grace_credits: 2 }
  let(:admin) { create :admin }
  let(:ta) { create :ta }
  let(:grouping) { create :grouping_with_inviter, assignment: assignment, inviter: student }
  let(:submission) { create :version_used_submission, grouping: grouping }
  let(:incomplete_result) { submission.current_result }
  let(:complete_result) { create :complete_result, submission: submission }
  let(:submission_file) { create :submission_file, submission: submission }
  let(:rubric_criterion) { create(:rubric_criterion, assignment: assignment) }
  let(:rubric_mark) { create :rubric_mark, result: incomplete_result, markable: rubric_criterion }
  let(:flexible_criterion) { create(:flexible_criterion, assignment: assignment) }
  let(:flexible_mark) { create :flexible_mark, result: incomplete_result, markable: flexible_criterion }

  SAMPLE_FILE_CONTENT = 'sample file content'.freeze
  SAMPLE_ERROR_MESSAGE = 'sample error message'.freeze
  SAMPLE_COMMENT = 'sample comment'.freeze
  SAMPLE_FILE_NAME = 'file.java'.freeze

  after(:each) do
    destroy_repos
  end

  def self.test_assigns_not_nil(key)
    it "should assign #{key}" do
      expect(assigns key).not_to be_nil
    end
  end

  def self.test_redirect_no_login(route_name)
    it "should be redirected from #{route_name}" do
      method(ROUTES[route_name]).call(route_name, params: { assignment_id: 1, submission_id: 1, id: 1 })
      expect(response).to redirect_to action: 'login', controller: 'main'
    end
  end

  def self.test_no_flash
    it 'should not display any flash messages' do
      expect(flash).to be_empty
    end
  end

  def self.test_unauthorized(route_name)
    it "should not be authorized to access #{route_name}" do
      method(ROUTES[route_name]).call(route_name, params: { assignment_id: assignment.id,
                                                            submission_id: submission.id,
                                                            id: incomplete_result.id })
      expect(response).to have_http_status(:missing)
    end
  end

  shared_examples 'download files' do
    context 'downloading a file' do
      context 'without permission' do
        before :each do
          allow_any_instance_of(ResultsController).to receive(:authorized_to_download?).and_return false
          get :download, params: { assignment_id: assignment.id,
                                   submission_id: submission.id,
                                   id: incomplete_result.id }
        end
        it { expect(response).to have_http_status(:missing) }
        test_no_flash
      end
      context 'with permission' do
        before :each do
          allow_any_instance_of(ResultsController).to receive(:authorized_to_download?).and_return true
        end
        context 'and without any file errors' do
          before :each do
            allow_any_instance_of(SubmissionFile).to receive(:retrieve_file).and_return SAMPLE_FILE_CONTENT
            get :download, params: { assignment_id: assignment.id,
                                     submission_id: submission.id,
                                     select_file_id: submission_file.id,
                                     id: incomplete_result.id }
          end
          it { expect(response).to have_http_status(:success) }
          test_no_flash
          it 'should have the correct content type' do
            expect(response.header['Content-Type']).to eq 'text/plain'
          end
          it 'should show the file content in the response body' do
            expect(response.body).to eq SAMPLE_FILE_CONTENT
          end
        end
        context 'and with a file error' do
          before :each do
            allow_any_instance_of(SubmissionFile).to receive(:retrieve_file).and_raise SAMPLE_ERROR_MESSAGE
            get :download, params: { assignment_id: assignment.id,
                                     submission_id: submission.id,
                                     select_file_id: submission_file.id,
                                     id: incomplete_result.id }
          end
          it { expect(response).to have_http_status(:redirect) }
          it 'should display a flash error' do
            expect(extract_text(flash[:error][0])).to eq SAMPLE_ERROR_MESSAGE
          end
        end
        context 'and with a supported image file shown in browser' do
          before :each do
            allow_any_instance_of(SubmissionFile).to receive(:is_supported_image?).and_return true
            allow_any_instance_of(SubmissionFile).to receive(:retrieve_file).and_return SAMPLE_FILE_CONTENT
            get :download, params: { assignment_id: assignment.id,
                                     submission_id: submission.id,
                                     select_file_id: submission_file.id,
                                     id: incomplete_result.id,
                                     show_in_browser: true }
          end
          it { expect(response).to have_http_status(:success) }
          test_no_flash
          it 'should have the correct content type' do
            expect(response.header['Content-Type']).to eq 'image'
          end
          it 'should show the file content in the response body' do
            expect(response.body).to eq SAMPLE_FILE_CONTENT
          end
        end
      end
    end
  end

  shared_examples 'shared ta and admin tests' do
    include_examples 'download files'
    context 'accessing next_grouping' do
      it 'should redirect when current grouping has a submission' do
        allow_any_instance_of(Grouping).to receive(:has_submission).and_return true
        get :next_grouping, params: { assignment_id: assignment.id, submission_id: submission.id,
                                      grouping_id: grouping.id, id: incomplete_result.id }
        expect(response).to have_http_status(:redirect)
      end
      it 'should redirect when current grouping does not have a submission' do
        allow_any_instance_of(Grouping).to receive(:has_submission).and_return false
        get :next_grouping, params: { assignment_id: assignment.id, submission_id: submission.id,
                                      grouping_id: grouping.id, id: incomplete_result.id }
        expect(response).to have_http_status(:redirect)
      end
    end
    context 'accessing toggle_marking_state' do
      context 'with a complete result' do
        before :each do
          post :toggle_marking_state, params: { assignment_id: assignment.id, submission_id: submission.id,
                                                id: complete_result.id }, xhr: true
        end
        it { expect(response).to have_http_status(:success) }
        # TODO: test that the grade distribution is refreshed
      end
    end
    context 'accessing download_zip' do
      before :each do
        grouping.group.access_repo do |repo|
          txn = repo.get_transaction('test')
          path = File.join(assignment.repository_folder, SAMPLE_FILE_NAME)
          txn.add(path, SAMPLE_FILE_CONTENT, '')
          repo.commit(txn)
          @submission = Submission.generate_new_submission(grouping, repo.get_latest_revision)
        end
        file = SubmissionFile.find_by_submission_id(@submission.id)
        @annotation = TextAnnotation.create  line_start: 1,
                                             line_end: 2,
                                             column_start: 1,
                                             column_end: 2,
                                             submission_file_id: file.id,
                                             is_remark: false,
                                             annotation_number: @submission.annotations.count + 1,
                                             annotation_text: create(:annotation_text, creator: admin),
                                             result: complete_result,
                                             creator: admin
        file_name_snippet = grouping.group.access_repo do |repo|
          "#{assignment.short_identifier}_#{grouping.group.group_name}_r#{repo.get_latest_revision.revision_identifier}"
        end
        @file_path_ann = File.join 'tmp', "#{file_name_snippet}_ann.zip"
        @file_path = File.join 'tmp', "#{file_name_snippet}.zip"
        submission_file_dir = "#{assignment.repository_folder}-#{grouping.group.repo_name}"
        @submission_file_path = File.join(submission_file_dir, SAMPLE_FILE_NAME)
      end
      after :each do
        FileUtils.rm_f @file_path_ann
        FileUtils.rm_f @file_path
      end
      context 'and including annotations' do
        before :each do
          get :download_zip, params: {  assignment_id: assignment.id,
                                        submission_id: @submission.id,
                                        id: @submission.id,
                                        grouping_id: grouping.id,
                                        include_annotations: 'true' }
        end
        after :each do
          FileUtils.rm_f @file_path_ann
        end
        it { expect(response).to have_http_status(:success) }
        it 'should have make the correct content type' do
          expect(response.header['Content-Type']).to eq 'application/zip'
        end
        it 'should create a zip file' do
          File.exist? @file_path_ann
        end
        it 'should create a zip file containing the submission file' do
          Zip::File.open(@file_path_ann) do |zip_file|
            expect(zip_file.find_entry(@submission_file_path)).not_to be_nil
          end
        end
        it 'should include the annotations in the file output' do
          Zip::File.open(@file_path_ann) do |zip_file|
            expect(zip_file.read(@submission_file_path)).to include(@annotation.annotation_text.content)
          end
        end
      end
      context 'and not including annotations' do
        before :each do
          get :download_zip, params: {  assignment_id: assignment.id,
                                        submission_id: @submission.id,
                                        id: @submission.id,
                                        grouping_id: grouping.id,
                                        include_annotations: 'false' }
        end
        after :each do
          FileUtils.rm_f @file_path
        end
        it { expect(response).to have_http_status(:success) }
        it 'should have make the correct content type' do
          expect(response.header['Content-Type']).to eq 'application/zip'
        end
        it 'should create a zip file' do
          File.exist? @file_path
        end
        it 'should create a zip file containing the submission file' do
          Zip::File.open(@file_path) do |zip_file|
            expect(zip_file.find_entry(@submission_file_path)).not_to be_nil
          end
        end
        it 'should not include the annotations in the file output' do
          Zip::File.open(@file_path) do |zip_file|
            expect(zip_file.read(@submission_file_path)).not_to include(@annotation.annotation_text.content)
          end
        end
      end
    end
    context 'accessing update_mark' do
      it 'should report an updated mark' do
        patch :update_mark, params: { assignment_id: assignment.id, submission_id: submission.id,
                                      id: incomplete_result.id, markable_id: rubric_mark.markable_id,
                                      markable_type: rubric_mark.markable_type,
                                      mark: 1 }, xhr: true
        expect(JSON.parse(response.body)['num_marked']).to eq 0
      end
      it { expect(response).to have_http_status(:redirect) }
      context 'but cannot save the mark' do
        before :each do
          allow_any_instance_of(Mark).to receive(:save).and_return false
          allow_any_instance_of(ActiveModel::Errors).to receive(:full_messages).and_return [SAMPLE_ERROR_MESSAGE]
          patch :update_mark, params: { assignment_id: assignment.id, submission_id: submission.id,
                                        id: incomplete_result.id, markable_id: rubric_mark.markable_id,
                                        markable_type: rubric_mark.markable_type,
                                        mark: 1 }, xhr: true
        end
        it { expect(response).to have_http_status(:bad_request) }
        it 'should report the correct error message' do
          expect(response.body).to match SAMPLE_ERROR_MESSAGE
        end
      end
    end
    context 'accessing view_mark' do
      before :each do
        get :view_marks, params: { assignment_id: assignment.id, submission_id: submission.id,
                                   id: incomplete_result.id }, xhr: true
      end
      it { expect(response).to have_http_status(:success) }
    end
    context 'accessing add_extra_mark' do
      context 'but cannot save the mark' do
        before :each do
          allow_any_instance_of(ExtraMark).to receive(:save).and_return false
          @old_mark = submission.get_latest_result.total_mark
          post :add_extra_mark, params: { assignment_id: assignment.id, submission_id: submission.id,
                                          id: submission.get_latest_result.id,
                                          extra_mark: { extra_mark: 1 } }, xhr: true
        end
        it { expect(response).to have_http_status(:bad_request) }
        it 'should not update the total mark' do
          expect(@old_mark).to eq(submission.get_latest_result.total_mark)
        end
      end
      context 'and can save the mark' do
        before :each do
          allow_any_instance_of(ExtraMark).to receive(:save).and_call_original
          @old_mark = submission.get_latest_result.total_mark
          post :add_extra_mark, params: { assignment_id: assignment.id, submission_id: submission.id,
                                          id: submission.get_latest_result.id,
                                          extra_mark: { extra_mark: 1 } }, xhr: true
        end
        it { expect(response).to have_http_status(:success) }
        it 'should update the total mark' do
          expect(@old_mark + 1).to eq(submission.get_latest_result.total_mark)
        end
      end
    end
    context 'accessing remove_extra_mark' do
      before :each do
        extra_mark = create(:extra_mark_points, result: submission.get_latest_result)
        submission.get_latest_result.update_total_mark
        @old_mark = submission.get_latest_result.total_mark
        post :remove_extra_mark, params: { assignment_id: assignment.id, submission_id: submission.id,
                                           id: extra_mark.id }, xhr: true
      end
      test_no_flash
      it { expect(response).to have_http_status(:success) }
      it 'should change the total value' do
        submission.get_latest_result.update_total_mark
        expect(@old_mark).not_to eq incomplete_result.total_mark
      end
    end
    context 'accessing update_overall_comment' do
      before :each do
        post :update_overall_comment, params: { assignment_id: assignment.id, submission_id: submission.id,
                                                id: incomplete_result.id,
                                                result: { overall_comment: SAMPLE_COMMENT } }, xhr: true
        incomplete_result.reload
      end
      it { expect(response).to have_http_status(:success) }
      it 'should update the overall comment' do
        expect(incomplete_result.overall_comment).to eq SAMPLE_COMMENT
      end
    end

    context 'accessing an assignment with deductive annotations' do
      it 'returns annotation data with criteria information' do
        assignment = create(:assignment_with_deductive_annotations)
        post :get_annotations, params: { assignment_id: assignment.id,
                                         submission_id: assignment.groupings.first.current_result.submission.id,
                                         id: assignment.groupings.first.current_result,
                                         format: :json }, xhr: true

        expect(response.parsed_body.first['criterion_name']).to eq assignment.flexible_criteria.first.name
        expect(response.parsed_body.first['criterion_id']).to eq assignment.flexible_criteria.first.id
        expect(response.parsed_body.first['deduction']).to eq 1.0
      end

      it 'returns annotation_category data with deductive information' do
        assignment = create(:assignment_with_deductive_annotations)
        category = assignment.annotation_categories.where.not(flexible_criterion: nil).first
        post :show, params: { assignment_id: assignment.id,
                              submission_id: assignment.groupings.first.current_result.submission.id,
                              id: assignment.groupings.first.current_result,
                              format: :json }, xhr: true

        expect(response.parsed_body['annotation_categories'].first['annotation_category_name'])
          .to eq "#{category.annotation_category_name}"\
                 "#{category.flexible_criterion_id.nil? ? '' : " [#{category.flexible_criterion.name}]"}"
        expect(response.parsed_body['annotation_categories'].first['texts'].first['deduction']).to eq 1.0
        expect(response.parsed_body['annotation_categories']
                   .first['flexible_criterion_id']).to eq category.flexible_criterion.id
      end
    end
  end

  ROUTES = { update_mark: :patch,
             edit: :get,
             download: :post,
             get_annotations: :get,
             add_extra_mark: :post,
             download_zip: :get,
             cancel_remark_request: :delete,
             delete_grace_period_deduction: :delete,
             next_grouping: :get,
             remove_extra_mark: :post,
             set_released_to_students: :post,
             update_overall_comment: :post,
             toggle_marking_state: :post,
             update_remark_request: :patch,
             update_positions: :get,
             view_marks: :get,
             add_tag: :post,
             remove_tag: :post,
             run_tests: :post,
             stop_test: :get,
             get_test_runs_instructors: :get,
             get_test_runs_instructors_released: :get }.freeze

  context 'A not logged in user' do
    [:edit,
     :next_grouping,
     :set_released_to_students,
     :toggle_marking_state,
     :update_overall_comment,
     :update_remark_request,
     :cancel_remark_request,
     :download,
     :update_mark,
     :view_marks,
     :add_extra_mark,
     :remove_extra_mark].each { |route_name| test_redirect_no_login(route_name) }
  end

  context 'A student' do
    before(:each) { sign_in student }
    [:edit,
     :next_grouping,
     :set_released_to_students,
     :toggle_marking_state,
     :update_overall_comment,
     :update_mark,
     :add_extra_mark,
     :remove_extra_mark].each { |route_name| test_unauthorized(route_name) }
    include_examples 'download files'
    context 'viewing a file' do
      context 'for a grouping with no submission' do
        before :each do
          allow_any_instance_of(Grouping).to receive(:has_submission?).and_return false
          get :view_marks, params: { assignment_id: assignment.id,
                                     submission_id: submission.id,
                                     id: incomplete_result.id }
        end
        it { expect(response).to render_template('results/student/no_submission') }
        it { expect(response).to have_http_status(:success) }
        test_assigns_not_nil :assignment
        test_assigns_not_nil :grouping
      end
      context 'for a grouping with a submission but no result' do
        before :each do
          allow_any_instance_of(Submission).to receive(:has_result?).and_return false
          get :view_marks, params: { assignment_id: assignment.id,
                                     submission_id: submission.id,
                                     id: incomplete_result.id }
        end
        it { expect(response).to render_template('results/student/no_result') }
        it { expect(response).to have_http_status(:success) }
        test_assigns_not_nil :assignment
        test_assigns_not_nil :grouping
        test_assigns_not_nil :submission
      end
      context 'for a grouping with an unreleased result' do
        before :each do
          allow_any_instance_of(Submission).to receive(:has_result?).and_return true
          allow_any_instance_of(Result).to receive(:released_to_students).and_return false
          get :view_marks, params: { assignment_id: assignment.id,
                                     submission_id: submission.id,
                                     id: incomplete_result.id }
        end
        it { expect(response).to render_template('results/student/no_result') }
        it { expect(response).to have_http_status(:success) }
        test_assigns_not_nil :assignment
        test_assigns_not_nil :grouping
        test_assigns_not_nil :submission
      end
      context 'and the result is available for viewing' do
        before :each do
          allow_any_instance_of(Submission).to receive(:has_result?).and_return true
          allow_any_instance_of(Result).to receive(:released_to_students).and_return true
          get :view_marks, params: { assignment_id: assignment.id,
                                     submission_id: submission.id,
                                     id: complete_result.id }
        end
        it { expect(response).to have_http_status(:success) }
        it { expect(response).to render_template(:view_marks) }
        test_assigns_not_nil :assignment
        test_assigns_not_nil :grouping
        test_assigns_not_nil :submission
        test_assigns_not_nil :result
        test_assigns_not_nil :mark_criteria
        test_assigns_not_nil :annotation_categories
        test_assigns_not_nil :group
        test_assigns_not_nil :files
        test_assigns_not_nil :extra_marks_points
        test_assigns_not_nil :extra_marks_percentage
      end
    end
  end
  context 'An admin' do
    before(:each) { sign_in admin }

    context 'accessing set_released_to_students' do
      before :each do
        get :set_released_to_students, params: { assignment_id: assignment.id, submission_id: submission.id,
                                                 id: complete_result.id, value: 'true' }, xhr: true
      end
      it { expect(response).to have_http_status(:success) }
      test_assigns_not_nil :result
    end
    include_examples 'shared ta and admin tests'

    describe '#delete_grace_period_deduction' do
      it 'deletes an existing grace period deduction' do
        expect(grouping.grace_period_deductions.exists?).to be false
        deduction = create(:grace_period_deduction,
                           membership: grouping.accepted_student_memberships.first,
                           deduction: 1)
        expect(grouping.grace_period_deductions.exists?).to be true
        delete :delete_grace_period_deduction,
               params: { assignment_id: assignment.id, submission_id: submission.id,
                         id: complete_result.id, deduction_id: deduction.id }
        expect(grouping.grace_period_deductions.exists?).to be false
      end

      it 'raises a RecordNotFound error when given a grace period deduction that does not exist' do
        expect do
          delete :delete_grace_period_deduction,
                 params: { assignment_id: assignment.id, submission_id: submission.id,
                           id: complete_result.id, deduction_id: 100 }
        end.to raise_error(ActiveRecord::RecordNotFound)
      end

      it 'raises a RecordNotFound error when given a grace period deduction for a different grouping' do
        student2 = create(:student, grace_credits: 2)
        grouping2 = create(:grouping_with_inviter, assignment: assignment, inviter: student2)
        submission2 = create(:version_used_submission, grouping: grouping2)
        create(:complete_result, submission: submission2)
        deduction = create(:grace_period_deduction,
                           membership: grouping2.accepted_student_memberships.first,
                           deduction: 1)
        expect do
          delete :delete_grace_period_deduction,
                 params: { assignment_id: assignment.id, submission_id: submission.id,
                           id: complete_result.id, deduction_id: deduction.id }
        end.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
    describe '#add_tag' do
      it 'adds a tag to a grouping' do
        tag = create(:tag)
        post :add_tag,
             params: { assignment_id: assignment.id, submission_id: submission.id,
                       id: complete_result.id, tag_id: tag.id }
        expect(complete_result.submission.grouping.tags.to_a).to eq [tag]
      end
    end

    describe '#remove_tag' do
      it 'removes a tag from a grouping' do
        tag = create(:tag)
        submission.grouping.tags << tag
        post :remove_tag,
             params: { assignment_id: assignment.id, submission_id: submission.id,
                       id: complete_result.id, tag_id: tag.id }
        expect(complete_result.submission.grouping.tags.size).to eq 0
      end
    end
  end
  context 'A TA' do
    before(:each) { sign_in ta }
    [:set_released_to_students].each { |route_name| test_unauthorized(route_name) }
    context 'accessing edit' do
      before :each do
        get :edit, params: { assignment_id: assignment.id, submission_id: submission.id,
                             id: incomplete_result.id }, xhr: true
      end
      test_no_flash
      it { expect(response).to render_template('edit') }
      it { expect(response).to have_http_status(:success) }
    end
    include_examples 'shared ta and admin tests'

    context 'when groups information is anonymized' do
      let(:data) { JSON.parse(response.body) }
      let!(:grace_period_deduction) do
        create(:grace_period_deduction, membership: grouping.accepted_student_memberships.first)
      end
      before :each do
        assignment.assignment_properties.update(anonymize_groups: true)
        get :show, params: { assignment_id: assignment.id, submission_id: submission.id,
                             id: incomplete_result.id }, xhr: true
      end

      it 'should anonymize the group names' do
        expect(data['group_name']).to eq "#{Group.model_name.human} #{data['grouping_id']}"
      end

      it 'should not report any grace token deductions' do
        expect(data['grace_token_deductions']).to eq []
      end
    end

    context 'when criteria are assigned to this grader' do
      let(:data) { JSON.parse(response.body) }
      let(:params) { { assignment_id: assignment.id, submission_id: submission.id, id: incomplete_result.id } }
      before :each do
        assignment.assignment_properties.update(assign_graders_to_criteria: true)
        create(:criterion_ta_association, criterion: rubric_mark.markable, ta: ta)
        get :show, params: params, xhr: true
      end

      it 'should include assigned criteria list' do
        expect(data['assigned_criteria']).to eq ["#{rubric_criterion.class}-#{rubric_criterion.id}"]
      end

      context 'when unassigned criteria are hidden from the grader' do
        before :each do
          assignment.assignment_properties.update(hide_unassigned_criteria: true)
        end

        it 'should only include marks for the assigned criteria' do
          expected = [[rubric_criterion.class.to_s, rubric_criterion.id]]
          expect(data['marks'].map { |m| [m['criterion_type'], m['id']] }).to eq expected
        end

        context 'when a remark request exists' do
          let(:remarked) do
            submission.make_remark_result
            submission.update(remark_request_timestamp: Time.zone.now)
            submission
          end
          let(:params) { { assignment_id: assignment.id, submission_id: remarked.id, id: incomplete_result.id } }

          it 'should only include marks for assigned criteria in the remark result' do
            expect(data['old_marks'].keys).to eq ["#{rubric_criterion.class}-#{rubric_criterion.id}"]
          end
        end
      end
    end

    context 'accessing update_mark' do
      it 'should not count completed groupings that are not assigned to the TA' do
        grouping2 = create(:grouping_with_inviter, assignment: assignment)
        create(:version_used_submission, grouping: grouping2)
        grouping2.current_result.update(marking_state: Result::MARKING_STATES[:complete])

        patch :update_mark, params: { assignment_id: assignment.id, submission_id: submission.id,
                                      id: incomplete_result.id, markable_id: rubric_mark.markable_id,
                                      markable_type: rubric_mark.markable_type,
                                      mark: 1 }, xhr: true
        expect(JSON.parse(response.body)['num_marked']).to eq 0
      end
    end
    describe '#add_tag' do
      it 'adds a tag to a grouping' do
        tag = create(:tag)
        post :add_tag,
             params: { assignment_id: assignment.id, submission_id: submission.id,
                       id: complete_result.id, tag_id: tag.id }
        expect(complete_result.submission.grouping.tags.to_a).to eq [tag]
      end
    end

    describe '#remove_tag' do
      it 'removes a tag from a grouping' do
        tag = create(:tag)
        submission.grouping.tags << tag
        post :remove_tag,
             params: { assignment_id: assignment.id, submission_id: submission.id,
                       id: complete_result.id, tag_id: tag.id }
        expect(complete_result.submission.grouping.tags.size).to eq 0
      end
    end
  end
end
