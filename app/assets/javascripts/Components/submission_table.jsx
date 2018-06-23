import React from 'react';
import {render} from 'react-dom';

import ReactTable from 'react-table';
import checkboxHOC from 'react-table/lib/hoc/selectTable';

const CheckboxTable = checkboxHOC(ReactTable);


class SubmissionTable extends React.Component {
  constructor() {
    super();
    this.state = {
      groupings: [],
      sections: {},
      selection: [],
      selectAll: false,
      loading: true,
    };
  }

  componentDidMount() {
    this.fetchData();
  }

  fetchData = () => {
    $.get({
      url: Routes.assignment_submissions_path(this.props.assignment_id),
      dataType: 'json',
    }).then(res => {
      this.setState({
        groupings: res.groupings,
        sections: res.sections,
        loading: false,
        selection: [],
        selectAll: false,
      });
    });
  };

  // From https://react-table.js.org/#/story/select-table-hoc.
  toggleSelection = (key, shift, row) => {
    let selection = [
      ...this.state.selection
    ];
    const keyIndex = selection.indexOf(key);
    if (keyIndex >= 0) {
      selection = [
        ...selection.slice(0, keyIndex),
        ...selection.slice(keyIndex + 1)
      ]
    } else {
      selection.push(key);
    }
    // update the state
    this.setState({ selection });
  };

  toggleAll = () => {
    const selectAll = !this.state.selectAll;
    const selection = [];
    if (selectAll) {
      // we need to get at the internals of ReactTable
      const wrappedInstance = this.checkboxTable.getWrappedInstance();
      // the 'sortedData' property contains the currently accessible records based on the filter and sort
      const currentRecords = wrappedInstance.getResolvedState().sortedData;
      // we just push all the IDs onto the selection array
      currentRecords.forEach((item) => {
        selection.push(item._original._id);
      })
    }
    this.setState({ selectAll, selection });
  };

  isSelected = (key) => {
    return this.state.selection.includes(key);
  };

  columns = () => [
    {
      show: false,
      accessor: '_id',
      id: '_id'
    },
    {
      Header: I18n.t('browse_submissions.group_name'),
      accessor: 'group_name',
      id: 'group_name',
      Cell: row => {
        let members = '';
        if (this.props.show_members) {
          members = ` (${row.original.members.join(', ')})`;
        }
        if (row.original.result_id) {
          const result_url = Routes.edit_assignment_submission_result_path(
            this.props.assignment_id,
            row.original.result_id,
            row.original.result_id,
          );
          return <a href={result_url}>{row.value + members}</a>;
        } else {
          return row.value + members;
        }
      },
      minWidth: 170,
      filterMethod: (filter, row) => {
        if (filter.value) {
          // Check group name
          if (row._original.group_name.includes(filter.value)) {
            return true;
          }

          // Check member names
          return row._original.members && row._original.members.some(
            (name) => name.includes(filter.value)
          );
        } else {
          return true;
        }
      },
    },
    {
      Header: I18n.t('browse_submissions.repository'),
      filterable: false,
      sortable: false,
      Cell: row => {
        return (
          <a href={Routes.repo_browser_assignment_submission_path(
                     this.props.assignment_id, row.original._id)}
             className={row.original.no_files ? 'no-files' : ''}
          >
            {row.original.group_name}
          </a>
        );
      },
      minWidth: 80,
    },
    {
      Header: I18n.t('activerecord.models.section', {count: 1}),
      accessor: 'section',
      id: 'section',
      show: this.props.show_sections,
      minWidth: 70,
      Cell: ({ value }) => {
        return this.state.sections[value] || ''
      },
      filterMethod: (filter, row) => {
        if (filter.value === 'all') {
          return true;
        } else {
          return this.state.sections[row[filter.id]] === filter.value;
        }
      },
      Filter: ({ filter, onChange }) =>
        <select
          onChange={event => onChange(event.target.value)}
          style={{ width: '100%' }}
          value={filter ? filter.value : 'all'}
        >
          <option value='all'>{I18n.t('all')}</option>
          {Object.entries(this.state.sections).map(
            kv => <option key={kv[1]} value={kv[1]}>{kv[1]}</option>)}
        </select>,
    },
    {
      Header: I18n.t('browse_submissions.commit_date'),
      accessor: 'submission_time',
      filterable: false,
      minWidth: 150,
    },
    {
      Header: I18n.t('browse_submissions.grace_credits_used'),
      accessor: 'grace_credits_used',
      show: this.props.show_grace_tokens,
      minWidth: 100,
      style: { textAlign: 'right' },
    },
    {
      Header: I18n.t('browse_submissions.marking_state'),
      accessor: 'marking_state',
      filterMethod: (filter, row) => {
        if (filter.value === 'all') {
          return true;
        } else {
          return filter.value === row[filter.id];
        }
      },
      Filter: ({ filter, onChange }) =>
        <select
          onChange={event => onChange(event.target.value)}
          style={{ width: '100%' }}
          value={filter ? filter.value : 'all'}
        >
          <option value='all'>{I18n.t('all')}</option>
          <option value={I18n.t('marking_state.not_collected')}>{I18n.t('marking_state.not_collected')}</option>
          <option value='incomplete'>{I18n.t('marking_state.in_progress')}</option>
          <option value='complete'>{I18n.t('marking_state.completed')}</option>
          <option value='released'>{I18n.t('marking_state.released')}</option>
          <option value='remark'>{I18n.t('marking_state.remark_requested')}</option>
        </select>,
      minWidth: 70
    },
    {
      Header: I18n.t('browse_submissions.final_grade'),
      accessor: 'final_grade',
      style: {textAlign: 'right'},
      minWidth: 80,
      filterable: false,
      defaultSortDesc: true,
    },
    {
      Header: I18n.t('browse_submissions.tags_used'),
      accessor: 'tags',
      Cell: row => (
        <div className="tag_list">
          {row.original.tags.map(tag =>
            <span key={`${row.original._id}-${tag}`}
              className="tag_element">
              {tag}
            </span>
          )}
        </div>
      ),
      minWidth: 80,
      sortable: false
    }
  ];

  // Custom getTrProps function to highlight submissions that have been collected.
  getTrProps = (state, ri, ci, instance) => {
    if (ri.original.marking_state === undefined ||
        ri.original.marking_state === I18n.t('marking_state.not_collected')) {
      return {ri};
    } else {
      return {ri, className: 'submission_collected'};
    }
  };

  // Submission table actions
  collectSubmissions = () => {
    if (!window.confirm(I18n.t('collect_submissions.results_loss_warning'))) {
      return;
    }

    $.post({
      url: Routes.collect_submissions_assignment_submissions_path(this.props.assignment_id),
      data: { groupings: this.state.selection },
    });
  };

  uncollectAllSubmissions = () => {
    if (!window.confirm(I18n.t('collect_submissions.undo_results_loss_warning'))) {
      return;
    }

    $.get({
      url: Routes.uncollect_all_submissions_assignment_submissions_path(this.props.assignment_id),
      data: { groupings: this.state.selection },
    });
  };

  downloadGroupingFiles = (event) => {
    if (!window.confirm(I18n.t('collect_submissions.marking_incomplete_warning'))) {
      event.preventDefault();
    }
  };

  runTests = () => {
    $.post({
      url: Routes.run_tests_assignment_submissions_path(this.props.assignment_id),
      data: { groupings: this.state.selection },
    });
  };

  releaseMarks = () => {
    $.post({
      url: Routes.update_submissions_assignment_submissions_path(this.props.assignment_id),
      data: {
        release_results: true,
        groupings: this.state.selection
      }
    }).then(this.fetchData);
  };

  unreleaseMarks = () => {
    $.post({
      url: Routes.update_submissions_assignment_submissions_path(this.props.assignment_id),
      data: {
        release_results: false,
        groupings: this.state.selection
      }
    }).then(this.fetchData);
  };

  render() {
    const { toggleSelection, toggleAll, isSelected } = this;
    const { selectAll, loading } = this.state;

    const checkboxProps = {
      selectAll,
      isSelected,
      toggleSelection,
      toggleAll,
      selectType: 'checkbox',
    };

    return (
      <div>
        <SubmissionsActionBox
          ref={(r) => this.actionBox = r}
          disabled={this.state.selection.length === 0}
          is_admin={this.props.is_admin}
          assignment_id={this.props.assignment_id}
          can_run_tests={this.props.can_run_tests}

          collectSubmissions={this.collectSubmissions}
          downloadGroupingFiles={this.downloadGroupingFiles}
          runTests={this.runTests}
          releaseMarks={this.releaseMarks}
          unreleaseMarks={this.unreleaseMarks}
        />
        <CheckboxTable
          ref={(r) => this.checkboxTable = r}

          data={this.state.groupings}
          columns={this.columns()}
          defaultSorted={[
            {
              id: 'group_name'
            }
          ]}
          filterable
          loading={loading}

          getTrProps={this.getTrProps}

          {...checkboxProps}
        />
      </div>
    );
  }
}


SubmissionTable.defaultProps = {
  is_admin: false,
  can_run_tests: false
};


class SubmissionsActionBox extends React.Component {
  constructor(props) {
    super(props);
    this.state = {
      button_disabled: false
    };
  }

  render = () => {
    let collectButton, runTestsButton, releaseMarksButton, unreleaseMarksButton;
    if (this.props.is_admin) {
      collectButton = (
        <button
          onClick={this.props.collectSubmissions}
          disabled={this.props.disabled}
        >
          {I18n.t('collect_submissions.collect')}
        </button>
      );
      // TODO: look into re-enabling undo collection
      // uncollectButton = (
      //   <button onClick={this.props.uncollectSubmissions}
      //           disabled={this.props.disabled}>
      //     {I18n.t('collect_submissions.uncollect_all')}
      //   </button>
      // );

      releaseMarksButton = (
        <button
          disabled={this.props.disabled}
          onClick={this.props.releaseMarks}>
          {I18n.t('release_marks')}
        </button>
      );
      unreleaseMarksButton = (
        <button
          disabled={this.props.disabled}
          onClick={this.props.unreleaseMarks}>
          {I18n.t('unrelease_marks')}
        </button>
      );
    }
    if (this.props.can_run_tests) {
      runTestsButton = (
        <button onClick={this.props.runTests}
                disabled={this.props.disabled}
        >
          {I18n.t('browse_submissions.run_tests')}
        </button>
      );
    }

    let downloadGroupingFilesButton = (
      <a
        href={Routes.download_groupings_files_assignment_submissions_path(this.props.assignment_id)}
        onClick={this.props.downloadGroupingFiles}
        download
        className="button"
      >
        {I18n.t('download_the', {item: I18n.t('browse_submissions.all_submissions')})}
      </a>
    );

    return (
      <div className='rt-action-box'>
        {collectButton}
        {downloadGroupingFilesButton}
        {runTestsButton}
        {releaseMarksButton}
        {unreleaseMarksButton}
      </div>
    );
  };
}

export function makeSubmissionTable(elem, props) {
  render(<SubmissionTable {...props} />, elem);
}
